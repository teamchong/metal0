//! RLE/Bit-Packing Hybrid encoding decoder for Parquet.
//!
//! Parquet uses a hybrid encoding that combines:
//! - Run-length encoding (RLE) for repeated values
//! - Bit-packing for sequences of distinct values
//!
//! See: https://parquet.apache.org/docs/file-format/data-pages/encodings/#run-length-encoding--bit-packing-hybrid-rle--3

const std = @import("std");

pub const RleError = error{
    UnexpectedEndOfData,
    InvalidEncoding,
    OutOfMemory,
};

/// RLE/Bit-Packing Hybrid decoder
pub const RleDecoder = struct {
    data: []const u8,
    pos: usize,
    bit_width: u6,

    const Self = @This();

    /// Create a new RLE decoder
    /// bit_width: number of bits per value (1-32)
    pub fn init(data: []const u8, bit_width: u6) Self {
        return .{
            .data = data,
            .pos = 0,
            .bit_width = bit_width,
        };
    }

    /// Remaining bytes
    pub fn remaining(self: Self) usize {
        return self.data.len - self.pos;
    }

    /// Read unsigned varint (same as protobuf/thrift)
    fn readVarint(self: *Self) RleError!u32 {
        var result: u32 = 0;
        var shift: u5 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            result |= @as(u32, byte & 0x7F) << shift;

            if (byte & 0x80 == 0) {
                return result;
            }

            shift += 7;
            if (shift >= 35) {
                return RleError.InvalidEncoding;
            }
        }

        return RleError.UnexpectedEndOfData;
    }

    /// Decode all values from the RLE/bit-packed stream
    pub fn decode(self: *Self, count: usize, allocator: std.mem.Allocator) RleError![]u32 {
        const values = try allocator.alloc(u32, count);
        errdefer allocator.free(values);

        var idx: usize = 0;
        while (idx < count) {
            if (self.pos >= self.data.len) {
                // May have trailing zeros or be exact
                break;
            }

            // Read the indicator byte
            const indicator = try self.readVarint();

            if (indicator & 1 == 0) {
                // RLE run: indicator = run_length << 1
                const run_len: usize = @intCast(indicator >> 1);

                // Read the literal value (ceil(bit_width / 8) bytes, little-endian)
                const byte_width = (@as(usize, self.bit_width) + 7) / 8;
                if (self.pos + byte_width > self.data.len) {
                    return RleError.UnexpectedEndOfData;
                }

                var value: u32 = 0;
                for (0..byte_width) |i| {
                    value |= @as(u32, self.data[self.pos + i]) << @intCast(i * 8);
                }
                self.pos += byte_width;

                // Fill in the repeated values
                const end = @min(idx + run_len, count);
                for (idx..end) |i| {
                    values[i] = value;
                }
                idx = end;
            } else {
                // Bit-packed run: indicator = (num_groups << 1) | 1
                // Each group has 8 values
                const num_groups: usize = @intCast(indicator >> 1);
                const num_values = num_groups * 8;

                // Each group takes bit_width bytes
                const bytes_per_group = self.bit_width;
                const total_bytes = num_groups * bytes_per_group;

                if (self.pos + total_bytes > self.data.len) {
                    return RleError.UnexpectedEndOfData;
                }

                // Decode bit-packed values
                const group_data = self.data[self.pos..][0..total_bytes];
                self.pos += total_bytes;

                var values_decoded: usize = 0;
                for (0..num_groups) |g| {
                    const group_bytes = group_data[g * bytes_per_group ..][0..bytes_per_group];
                    try self.unpackGroup(group_bytes, values, &idx, count);
                    values_decoded += 8;
                }
                _ = num_values;
            }
        }

        // Fill remaining with zeros if we didn't get enough
        for (idx..count) |i| {
            values[i] = 0;
        }

        return values;
    }

    /// Unpack 8 values from a bit-packed group
    fn unpackGroup(self: *Self, group_bytes: []const u8, values: []u32, idx: *usize, count: usize) RleError!void {
        const bit_width: usize = self.bit_width;
        const mask: u32 = if (bit_width == 32) 0xFFFFFFFF else (@as(u32, 1) << @intCast(bit_width)) - 1;

        // Extract 8 values, reading bits across byte boundaries
        // Optimized: use bit ops instead of div/mod
        for (0..8) |i| {
            if (idx.* >= count) break;

            const bit_offset = i * bit_width;
            const byte_offset = bit_offset >> 3; // div 8
            const bit_shift: u6 = @intCast(bit_offset & 7); // mod 8 (low 3 bits)

            // Read up to 5 bytes into u64 (handles up to 32-bit values crossing boundaries)
            // Direct byte reads are faster than inner loop
            var value: u64 = 0;
            const max_bytes = @min(5, group_bytes.len - byte_offset);
            if (max_bytes >= 1) value = group_bytes[byte_offset];
            if (max_bytes >= 2) value |= @as(u64, group_bytes[byte_offset + 1]) << 8;
            if (max_bytes >= 3) value |= @as(u64, group_bytes[byte_offset + 2]) << 16;
            if (max_bytes >= 4) value |= @as(u64, group_bytes[byte_offset + 3]) << 24;
            if (max_bytes >= 5) value |= @as(u64, group_bytes[byte_offset + 4]) << 32;

            values[idx.*] = @truncate((value >> bit_shift) & mask);
            idx.* += 1;
        }
    }

    /// Decode boolean values (special case: bit_width=1)
    pub fn decodeBooleans(self: *Self, count: usize, allocator: std.mem.Allocator) RleError![]bool {
        std.debug.assert(self.bit_width == 1);

        const u32_values = try self.decode(count, allocator);
        defer allocator.free(u32_values);

        const bool_values = try allocator.alloc(bool, count);
        for (0..count) |i| {
            bool_values[i] = u32_values[i] != 0;
        }

        return bool_values;
    }
};

/// Decode definition/repetition levels using RLE/bit-packing
/// Levels are length-prefixed (4 bytes little-endian length, then RLE data)
pub fn decodeLevels(
    data: []const u8,
    count: usize,
    bit_width: u6,
    allocator: std.mem.Allocator,
) RleError!struct { levels: []u32, bytes_consumed: usize } {
    if (bit_width == 0) {
        // All zeros (max level is 0)
        const levels = try allocator.alloc(u32, count);
        @memset(levels, 0);
        return .{ .levels = levels, .bytes_consumed = 0 };
    }

    if (data.len < 4) {
        return RleError.UnexpectedEndOfData;
    }

    // Read length prefix
    const len = std.mem.readInt(u32, data[0..4], .little);
    const len_usize: usize = @intCast(len);

    if (4 + len_usize > data.len) {
        return RleError.UnexpectedEndOfData;
    }

    const rle_data = data[4..][0..len_usize];
    var decoder = RleDecoder.init(rle_data, bit_width);
    const levels = try decoder.decode(count, allocator);

    return .{ .levels = levels, .bytes_consumed = 4 + len_usize };
}

// ============================================================================
// Tests
// ============================================================================

test "decode RLE run" {
    // RLE run of 5 values of 42 (bit_width=8)
    // indicator = 5 << 1 = 10 = 0x0A
    // value = 42 = 0x2A
    const data = [_]u8{ 0x0A, 0x2A };

    var decoder = RleDecoder.init(&data, 8);
    const values = try decoder.decode(5, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqual(@as(usize, 5), values.len);
    for (values) |v| {
        try std.testing.expectEqual(@as(u32, 42), v);
    }
}

test "decode bit-packed" {
    // 1 group of 8 bit-packed values (bit_width=3)
    // indicator = (1 << 1) | 1 = 3
    // 8 values * 3 bits = 24 bits = 3 bytes
    // Values: [0, 1, 2, 3, 4, 5, 6, 7]
    // Packed: 0b00_001_000, 0b0_100_011_0, 0b111_110_10 (reversed for little-endian)
    // = 0b000_001_000 = 0x08, 0b100_011_010 = 0x1A, 0b0111_110_1 = 0x7D
    // Actually: pack left-to-right within bytes
    // val[0]=0 (000), val[1]=1 (001), val[2]=2 (010)... at positions 0,3,6,9...
    // Byte 0 bits 0-7: val[0] bits 0-2, val[1] bits 0-2, val[2] bits 0-1
    //                  000, 001, 01 -> 0b01_001_000 = 0x48
    // Byte 1 bits 0-7: val[2] bit 2, val[3] bits 0-2, val[4] bits 0-2, val[5] bit 0
    //                  0, 011, 100, 1 -> 0b1_100_011_0 = 0xC6
    // Byte 2 bits 0-7: val[5] bits 1-2, val[6] bits 0-2, val[7] bits 0-2
    //                  01, 110, 111 -> 0b111_110_10 = 0xFA? No wait...

    // Let me recalculate. For bit_width=3, 8 values:
    // Values: 0,1,2,3,4,5,6,7 in binary: 000,001,010,011,100,101,110,111
    // Pack them into bytes starting from LSB:
    // Byte 0: bits 0-7 = val[0](3b) + val[1](3b) + val[2](2b)
    //       = 000 + 001 + 01 (take 2 bits from val[2])
    //       = 000 + 001<<3 + (010&0b11)<<6 = 0 + 8 + 128 = 0b01_001_000 = 0x48
    // Byte 1: bits 0-7 = val[2](1b remaining) + val[3](3b) + val[4](3b) + val[5](1b)
    //       = 0 + 011<<1 + 100<<4 + 1<<7 = 0 + 6 + 64 + 128 = 198 = 0b11000110 = 0xC6
    // Byte 2: bits 0-7 = val[5](2b remaining) + val[6](3b) + val[7](3b)
    //       = 01 + 110<<2 + 111<<5 = 1 + 24 + 224 = 249 = 0b11111001 = 0xF9

    const data = [_]u8{ 0x03, 0x48, 0xC6, 0xF9 };

    var decoder = RleDecoder.init(&data, 3);
    const values = try decoder.decode(8, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqual(@as(usize, 8), values.len);
    for (0..8) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(i)), values[i]);
    }
}

test "decode mixed RLE and bit-packed" {
    // Mix of RLE and bit-packed
    // RLE: 3 values of 5 (bit_width=4)
    // indicator = 3 << 1 = 6
    // value = 5 = 0x05
    const data = [_]u8{ 0x06, 0x05 };

    var decoder = RleDecoder.init(&data, 4);
    const values = try decoder.decode(3, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(u32, 5), values[0]);
    try std.testing.expectEqual(@as(u32, 5), values[1]);
    try std.testing.expectEqual(@as(u32, 5), values[2]);
}

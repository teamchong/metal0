//! PLAIN encoding decoder for Parquet.
//!
//! PLAIN is the simplest encoding where values are stored back-to-back.
//! See: https://parquet.apache.org/docs/file-format/data-pages/encodings/

const std = @import("std");
const meta = @import("lanceql.format").parquet_metadata;
const Type = meta.Type;

pub const PlainError = error{
    UnexpectedEndOfData,
    InvalidType,
    OutOfMemory,
};

/// PLAIN decoder
pub const PlainDecoder = struct {
    data: []const u8,
    pos: usize,

    const Self = @This();

    pub fn init(data: []const u8) Self {
        return .{
            .data = data,
            .pos = 0,
        };
    }

    /// Remaining bytes
    pub fn remaining(self: Self) usize {
        return self.data.len - self.pos;
    }

    // ========================================================================
    // Boolean decoding
    // ========================================================================

    /// Read booleans (bit-packed, 1 bit per value)
    pub fn readBooleans(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![]bool {
        const bytes_needed = (count + 7) / 8;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc(bool, count);
        errdefer allocator.free(values);

        // Process 8 values at a time from each byte (avoids div/mod per value)
        const full_bytes = count / 8;
        var idx: usize = 0;

        for (0..full_bytes) |byte_i| {
            const byte = self.data[self.pos + byte_i];
            // Unroll 8 bits
            values[idx] = (byte & 0x01) != 0;
            values[idx + 1] = (byte & 0x02) != 0;
            values[idx + 2] = (byte & 0x04) != 0;
            values[idx + 3] = (byte & 0x08) != 0;
            values[idx + 4] = (byte & 0x10) != 0;
            values[idx + 5] = (byte & 0x20) != 0;
            values[idx + 6] = (byte & 0x40) != 0;
            values[idx + 7] = (byte & 0x80) != 0;
            idx += 8;
        }

        // Handle remaining bits
        if (idx < count) {
            const byte = self.data[self.pos + full_bytes];
            var bit: u3 = 0;
            while (idx < count) : ({
                idx += 1;
                bit += 1;
            }) {
                values[idx] = ((byte >> bit) & 1) != 0;
            }
        }

        self.pos += bytes_needed;
        return values;
    }

    // ========================================================================
    // Integer decoding
    // ========================================================================

    /// Read INT32 values (4 bytes each, little-endian)
    pub fn readInt32(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![]i32 {
        const bytes_needed = count * 4;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc(i32, count);
        errdefer allocator.free(values);

        // Direct memcpy - Parquet uses little-endian, same as x86/ARM
        const src = self.data[self.pos..][0..bytes_needed];
        @memcpy(std.mem.sliceAsBytes(values), src);

        self.pos += bytes_needed;
        return values;
    }

    /// Read INT64 values (8 bytes each, little-endian)
    pub fn readInt64(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![]i64 {
        const bytes_needed = count * 8;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc(i64, count);
        errdefer allocator.free(values);

        // Direct memcpy - Parquet uses little-endian, same as x86/ARM
        const src = self.data[self.pos..][0..bytes_needed];
        @memcpy(std.mem.sliceAsBytes(values), src);

        self.pos += bytes_needed;
        return values;
    }

    /// Read INT96 values (12 bytes each, deprecated timestamp format)
    pub fn readInt96(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![][12]u8 {
        const bytes_needed = count * 12;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc([12]u8, count);
        errdefer allocator.free(values);

        for (0..count) |i| {
            const offset = self.pos + i * 12;
            @memcpy(&values[i], self.data[offset..][0..12]);
        }

        self.pos += bytes_needed;
        return values;
    }

    // ========================================================================
    // Floating point decoding
    // ========================================================================

    /// Read FLOAT values (4 bytes each, IEEE 754)
    pub fn readFloat(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![]f32 {
        const bytes_needed = count * 4;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc(f32, count);
        errdefer allocator.free(values);

        // Direct memcpy - IEEE 754 little-endian same as x86/ARM
        const src = self.data[self.pos..][0..bytes_needed];
        @memcpy(std.mem.sliceAsBytes(values), src);

        self.pos += bytes_needed;
        return values;
    }

    /// Read DOUBLE values (8 bytes each, IEEE 754)
    pub fn readDouble(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![]f64 {
        const bytes_needed = count * 8;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc(f64, count);
        errdefer allocator.free(values);

        // Direct memcpy - IEEE 754 little-endian same as x86/ARM
        const src = self.data[self.pos..][0..bytes_needed];
        @memcpy(std.mem.sliceAsBytes(values), src);

        self.pos += bytes_needed;
        return values;
    }

    // ========================================================================
    // Binary/String decoding
    // ========================================================================

    /// Read BYTE_ARRAY values (length-prefixed)
    /// Returns slices into the original data buffer
    pub fn readByteArray(self: *Self, count: usize, allocator: std.mem.Allocator) PlainError![][]const u8 {
        const values = try allocator.alloc([]const u8, count);
        errdefer allocator.free(values);

        for (0..count) |i| {
            if (self.pos + 4 > self.data.len) {
                return PlainError.UnexpectedEndOfData;
            }

            const len = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
            self.pos += 4;

            const len_usize: usize = @intCast(len);
            if (self.pos + len_usize > self.data.len) {
                return PlainError.UnexpectedEndOfData;
            }

            values[i] = self.data[self.pos..][0..len_usize];
            self.pos += len_usize;
        }

        return values;
    }

    /// Read FIXED_LEN_BYTE_ARRAY values
    pub fn readFixedLenByteArray(self: *Self, count: usize, type_length: usize, allocator: std.mem.Allocator) PlainError![][]const u8 {
        const bytes_needed = count * type_length;
        if (self.pos + bytes_needed > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const values = try allocator.alloc([]const u8, count);
        errdefer allocator.free(values);

        for (0..count) |i| {
            const offset = self.pos + i * type_length;
            values[i] = self.data[offset..][0..type_length];
        }

        self.pos += bytes_needed;
        return values;
    }

    // ========================================================================
    // Raw data access
    // ========================================================================

    /// Read raw bytes
    pub fn readBytes(self: *Self, count: usize) PlainError![]const u8 {
        if (self.pos + count > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }

        const result = self.data[self.pos..][0..count];
        self.pos += count;
        return result;
    }

    /// Skip bytes
    pub fn skip(self: *Self, count: usize) PlainError!void {
        if (self.pos + count > self.data.len) {
            return PlainError.UnexpectedEndOfData;
        }
        self.pos += count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "read int32" {
    // Values: [1, 2, 256, -1]
    const data = [_]u8{
        0x01, 0x00, 0x00, 0x00, // 1
        0x02, 0x00, 0x00, 0x00, // 2
        0x00, 0x01, 0x00, 0x00, // 256
        0xFF, 0xFF, 0xFF, 0xFF, // -1
    };

    var decoder = PlainDecoder.init(&data);
    const values = try decoder.readInt32(4, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqual(@as(i32, 1), values[0]);
    try std.testing.expectEqual(@as(i32, 2), values[1]);
    try std.testing.expectEqual(@as(i32, 256), values[2]);
    try std.testing.expectEqual(@as(i32, -1), values[3]);
}

test "read int64" {
    const data = [_]u8{
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // -1
    };

    var decoder = PlainDecoder.init(&data);
    const values = try decoder.readInt64(2, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqual(@as(i64, 1), values[0]);
    try std.testing.expectEqual(@as(i64, -1), values[1]);
}

test "read double" {
    var data: [16]u8 = undefined;
    const val1: f64 = 3.14159;
    const val2: f64 = -2.71828;
    std.mem.writeInt(u64, data[0..8], @bitCast(val1), .little);
    std.mem.writeInt(u64, data[8..16], @bitCast(val2), .little);

    var decoder = PlainDecoder.init(&data);
    const values = try decoder.readDouble(2, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectApproxEqAbs(val1, values[0], 0.00001);
    try std.testing.expectApproxEqAbs(val2, values[1], 0.00001);
}

test "read byte_array" {
    // Two strings: "hello" and "world"
    const data = [_]u8{
        0x05, 0x00, 0x00, 0x00, // length 5
        'h',  'e',  'l',  'l',  'o', // "hello"
        0x05, 0x00, 0x00, 0x00, // length 5
        'w',  'o',  'r',  'l',  'd', // "world"
    };

    var decoder = PlainDecoder.init(&data);
    const values = try decoder.readByteArray(2, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expectEqualStrings("hello", values[0]);
    try std.testing.expectEqualStrings("world", values[1]);
}

test "read booleans" {
    // 8 booleans packed into 1 byte: true, false, true, true, false, false, true, false
    // = 0b01001101 = 0x4D
    const data = [_]u8{0x4D};

    var decoder = PlainDecoder.init(&data);
    const values = try decoder.readBooleans(8, std.testing.allocator);
    defer std.testing.allocator.free(values);

    try std.testing.expect(values[0] == true);
    try std.testing.expect(values[1] == false);
    try std.testing.expect(values[2] == true);
    try std.testing.expect(values[3] == true);
    try std.testing.expect(values[4] == false);
    try std.testing.expect(values[5] == false);
    try std.testing.expect(values[6] == true);
    try std.testing.expect(values[7] == false);
}

//! Thrift TCompactProtocol decoder.
//!
//! Implements the Thrift Compact Protocol for decoding Parquet metadata.
//! See: https://github.com/apache/thrift/blob/master/doc/specs/thrift-compact-protocol.md
//!
//! Compact Protocol uses:
//! - Varints with ZigZag encoding for integers
//! - Delta encoding for field IDs (saves bytes for sequential fields)
//! - Type IDs encoded in 4 bits

const std = @import("std");

/// Thrift Compact Protocol type IDs (4 bits)
pub const CompactType = enum(u4) {
    stop = 0, // End of struct
    bool_true = 1, // Boolean true (no data)
    bool_false = 2, // Boolean false (no data)
    i8 = 3, // 1-byte signed integer
    i16 = 4, // Varint (zigzag)
    i32 = 5, // Varint (zigzag)
    i64 = 6, // Varint (zigzag)
    double = 7, // 8 bytes IEEE 754
    binary = 8, // Length-prefixed bytes (string)
    list = 9, // Element type + size + elements
    set = 10, // Same as list
    map = 11, // Key/value types + size + pairs
    struct_type = 12, // Nested struct

    pub fn fromU4(val: u4) ?CompactType {
        return std.meta.intToEnum(CompactType, val) catch null;
    }
};

/// Errors during Thrift decoding
pub const ThriftError = error{
    UnexpectedEndOfData,
    MalformedVarint,
    InvalidType,
    InvalidFieldDelta,
    OutOfMemory,
};

/// Thrift Compact Protocol decoder
pub const ThriftDecoder = struct {
    data: []const u8,
    pos: usize,
    /// Last field ID for delta encoding
    last_field_id: i16,

    const Self = @This();

    /// Create a new decoder
    pub fn init(data: []const u8) Self {
        return .{
            .data = data,
            .pos = 0,
            .last_field_id = 0,
        };
    }

    /// Check if more data available
    pub fn hasMore(self: Self) bool {
        return self.pos < self.data.len;
    }

    /// Get remaining bytes
    pub fn remaining(self: Self) usize {
        return self.data.len - self.pos;
    }

    /// Read a single byte
    pub fn readByte(self: *Self) ThriftError!u8 {
        if (self.pos >= self.data.len) {
            return ThriftError.UnexpectedEndOfData;
        }
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    /// Read unsigned varint (same as protobuf)
    pub fn readVarint(self: *Self) ThriftError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            result |= @as(u64, byte & 0x7F) << shift;

            if (byte & 0x80 == 0) {
                return result;
            }

            shift += 7;
            if (shift >= 70) {
                return ThriftError.MalformedVarint;
            }
        }

        return ThriftError.UnexpectedEndOfData;
    }

    /// Read signed varint with ZigZag decoding
    pub fn readZigZag(self: *Self) ThriftError!i64 {
        const n = try self.readVarint();
        // ZigZag decode: (n >> 1) ^ -(n & 1)
        return @as(i64, @bitCast(n >> 1)) ^ -@as(i64, @intCast(n & 1));
    }

    /// Read i16 (zigzag varint)
    pub fn readI16(self: *Self) ThriftError!i16 {
        const val = try self.readZigZag();
        return @intCast(val);
    }

    /// Read i32 (zigzag varint)
    pub fn readI32(self: *Self) ThriftError!i32 {
        const val = try self.readZigZag();
        return @intCast(val);
    }

    /// Read i64 (zigzag varint)
    pub fn readI64(self: *Self) ThriftError!i64 {
        return self.readZigZag();
    }

    /// Read double (8 bytes, little-endian IEEE 754)
    pub fn readDouble(self: *Self) ThriftError!f64 {
        if (self.pos + 8 > self.data.len) {
            return ThriftError.UnexpectedEndOfData;
        }
        const bits = std.mem.readInt(u64, self.data[self.pos..][0..8], .little);
        self.pos += 8;
        return @bitCast(bits);
    }

    /// Read binary/string (length-prefixed)
    pub fn readBinary(self: *Self) ThriftError![]const u8 {
        const len = try self.readVarint();
        const len_usize: usize = @intCast(len);

        if (self.pos + len_usize > self.data.len) {
            return ThriftError.UnexpectedEndOfData;
        }

        const result = self.data[self.pos..][0..len_usize];
        self.pos += len_usize;
        return result;
    }

    /// Read string as slice (alias for readBinary)
    pub fn readString(self: *Self) ThriftError![]const u8 {
        return self.readBinary();
    }

    /// Read field header
    ///
    /// Returns field ID and type. Field ID uses delta encoding:
    /// - If high 4 bits of type byte are non-zero, that's the delta from last field
    /// - If high 4 bits are zero, field ID is in next zigzag varint
    ///
    /// Returns null if STOP type encountered (end of struct)
    pub fn readFieldHeader(self: *Self) ThriftError!?struct { field_id: i16, field_type: CompactType } {
        const type_byte = try self.readByte();

        // Type is in low 4 bits
        const type_id: u4 = @truncate(type_byte);

        // STOP means end of struct
        if (type_id == 0) {
            return null;
        }

        const field_type = CompactType.fromU4(type_id) orelse return ThriftError.InvalidType;

        // Delta is in high 4 bits
        const delta: u4 = @truncate(type_byte >> 4);

        const field_id: i16 = if (delta == 0) blk: {
            // Full field ID follows as zigzag varint
            break :blk try self.readI16();
        } else blk: {
            // Delta encoding
            break :blk self.last_field_id + @as(i16, delta);
        };

        self.last_field_id = field_id;

        return .{
            .field_id = field_id,
            .field_type = field_type,
        };
    }

    /// Read a boolean field
    /// Note: In compact protocol, bool value is encoded in the type:
    /// - bool_true (1) means true
    /// - bool_false (2) means false
    pub fn readBoolFromType(field_type: CompactType) bool {
        return field_type == .bool_true;
    }

    /// Read list header
    /// Returns element type and count
    pub fn readListHeader(self: *Self) ThriftError!struct { elem_type: CompactType, count: usize } {
        const header = try self.readByte();

        // High 4 bits: size (if < 15) or 0xF meaning size follows
        const size_nibble: u4 = @truncate(header >> 4);
        const elem_type_id: u4 = @truncate(header);

        const elem_type = CompactType.fromU4(elem_type_id) orelse return ThriftError.InvalidType;

        const count: usize = if (size_nibble == 0xF) blk: {
            // Size is in following varint
            break :blk @intCast(try self.readVarint());
        } else blk: {
            break :blk size_nibble;
        };

        return .{
            .elem_type = elem_type,
            .count = count,
        };
    }

    /// Read map header
    /// Returns key type, value type, and count
    pub fn readMapHeader(self: *Self) ThriftError!struct { key_type: CompactType, value_type: CompactType, count: usize } {
        const count_raw = try self.readVarint();

        if (count_raw == 0) {
            // Empty map
            return .{
                .key_type = .stop,
                .value_type = .stop,
                .count = 0,
            };
        }

        const types_byte = try self.readByte();
        const key_type_id: u4 = @truncate(types_byte >> 4);
        const value_type_id: u4 = @truncate(types_byte);

        return .{
            .key_type = CompactType.fromU4(key_type_id) orelse return ThriftError.InvalidType,
            .value_type = CompactType.fromU4(value_type_id) orelse return ThriftError.InvalidType,
            .count = @intCast(count_raw),
        };
    }

    /// Skip a field based on its type
    pub fn skipField(self: *Self, field_type: CompactType) ThriftError!void {
        switch (field_type) {
            .stop => {},
            .bool_true, .bool_false => {},
            .i8 => {
                if (self.pos >= self.data.len) return ThriftError.UnexpectedEndOfData;
                self.pos += 1;
            },
            .i16, .i32, .i64 => _ = try self.readVarint(),
            .double => {
                if (self.pos + 8 > self.data.len) return ThriftError.UnexpectedEndOfData;
                self.pos += 8;
            },
            .binary => _ = try self.readBinary(),
            .list, .set => {
                const header = try self.readListHeader();
                for (0..header.count) |_| {
                    try self.skipField(header.elem_type);
                }
            },
            .map => {
                const header = try self.readMapHeader();
                for (0..header.count) |_| {
                    try self.skipField(header.key_type);
                    try self.skipField(header.value_type);
                }
            },
            .struct_type => {
                // Save parent's field ID tracking
                const saved_field_id = self.last_field_id;
                self.last_field_id = 0;

                // Skip nested struct by reading until STOP
                while (try self.readFieldHeader()) |field| {
                    try self.skipField(field.field_type);
                }

                // Restore parent's field ID tracking
                self.last_field_id = saved_field_id;
            },
        }
    }

    /// Create a sub-decoder for nested struct
    /// Useful when you want to decode a struct's raw bytes separately
    pub fn subDecoder(self: *Self, len: usize) ThriftError!Self {
        if (self.pos + len > self.data.len) {
            return ThriftError.UnexpectedEndOfData;
        }
        const sub = Self.init(self.data[self.pos..][0..len]);
        self.pos += len;
        return sub;
    }

    /// Reset field ID tracking (call when entering a new struct)
    pub fn resetFieldId(self: *Self) void {
        self.last_field_id = 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "read varint single byte" {
    var decoder = ThriftDecoder.init(&[_]u8{0x01});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 1), val);
}

test "read varint multi byte" {
    // 300 = 0xAC 0x02
    var decoder = ThriftDecoder.init(&[_]u8{ 0xAC, 0x02 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 300), val);
}

test "read zigzag positive" {
    // ZigZag: 1 -> 2
    var decoder = ThriftDecoder.init(&[_]u8{0x02});
    const val = try decoder.readZigZag();
    try std.testing.expectEqual(@as(i64, 1), val);
}

test "read zigzag negative" {
    // ZigZag: -1 -> 1
    var decoder = ThriftDecoder.init(&[_]u8{0x01});
    const val = try decoder.readZigZag();
    try std.testing.expectEqual(@as(i64, -1), val);
}

test "read zigzag larger negative" {
    // ZigZag: -2 -> 3
    var decoder = ThriftDecoder.init(&[_]u8{0x03});
    const val = try decoder.readZigZag();
    try std.testing.expectEqual(@as(i64, -2), val);
}

test "read binary" {
    // Length 5, then "hello"
    var decoder = ThriftDecoder.init(&[_]u8{ 0x05, 'h', 'e', 'l', 'l', 'o' });
    const bytes = try decoder.readBinary();
    try std.testing.expectEqualStrings("hello", bytes);
}

test "read field header with delta" {
    // Delta=1, type=i32(5): 0x15
    var decoder = ThriftDecoder.init(&[_]u8{0x15});
    const header = try decoder.readFieldHeader();
    try std.testing.expect(header != null);
    try std.testing.expectEqual(@as(i16, 1), header.?.field_id);
    try std.testing.expectEqual(CompactType.i32, header.?.field_type);
}

test "read field header sequential" {
    // Two fields with delta encoding
    // Field 1, type i32: delta=1, type=5 -> 0x15
    // Field 2, type i64: delta=1, type=6 -> 0x16
    var decoder = ThriftDecoder.init(&[_]u8{ 0x15, 0x16 });

    const h1 = try decoder.readFieldHeader();
    try std.testing.expect(h1 != null);
    try std.testing.expectEqual(@as(i16, 1), h1.?.field_id);

    const h2 = try decoder.readFieldHeader();
    try std.testing.expect(h2 != null);
    try std.testing.expectEqual(@as(i16, 2), h2.?.field_id);
}

test "read field header full field id" {
    // Field 16, type binary: delta=0, type=8, then zigzag(16)=32
    // 0x08 (delta=0, type=binary), 0x20 (zigzag 16)
    var decoder = ThriftDecoder.init(&[_]u8{ 0x08, 0x20 });
    const header = try decoder.readFieldHeader();
    try std.testing.expect(header != null);
    try std.testing.expectEqual(@as(i16, 16), header.?.field_id);
    try std.testing.expectEqual(CompactType.binary, header.?.field_type);
}

test "read stop" {
    var decoder = ThriftDecoder.init(&[_]u8{0x00});
    const header = try decoder.readFieldHeader();
    try std.testing.expect(header == null);
}

test "read list header small" {
    // List with 3 elements of type i32: 0x35
    var decoder = ThriftDecoder.init(&[_]u8{0x35});
    const header = try decoder.readListHeader();
    try std.testing.expectEqual(@as(usize, 3), header.count);
    try std.testing.expectEqual(CompactType.i32, header.elem_type);
}

test "read list header large" {
    // List with 20 elements of type binary: 0xF8, varint(20)
    var decoder = ThriftDecoder.init(&[_]u8{ 0xF8, 0x14 });
    const header = try decoder.readListHeader();
    try std.testing.expectEqual(@as(usize, 20), header.count);
    try std.testing.expectEqual(CompactType.binary, header.elem_type);
}

test "read double" {
    var data: [8]u8 = undefined;
    const val: f64 = 3.14159;
    std.mem.writeInt(u64, &data, @bitCast(val), .little);

    var decoder = ThriftDecoder.init(&data);
    const result = try decoder.readDouble();
    try std.testing.expectApproxEqAbs(val, result, 0.00001);
}

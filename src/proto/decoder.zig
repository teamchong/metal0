//! Protobuf wire format decoder.
//!
//! Implements the protobuf binary wire format for decoding messages.
//! See: https://protobuf.dev/programming-guides/encoding/
//!
//! Wire types:
//! - 0 (Varint): int32, int64, uint32, uint64, sint32, sint64, bool, enum
//! - 1 (64-bit): fixed64, sfixed64, double
//! - 2 (Length-delimited): string, bytes, embedded messages, packed repeated fields
//! - 5 (32-bit): fixed32, sfixed32, float

const std = @import("std");

/// Protobuf wire types
pub const WireType = enum(u3) {
    /// Variable-length integer (int32, int64, uint32, uint64, bool, enum)
    varint = 0,
    /// Fixed 64-bit value (fixed64, sfixed64, double)
    fixed64 = 1,
    /// Length-delimited (string, bytes, embedded messages, packed repeated)
    length_delimited = 2,
    /// Start group (deprecated)
    start_group = 3,
    /// End group (deprecated)
    end_group = 4,
    /// Fixed 32-bit value (fixed32, sfixed32, float)
    fixed32 = 5,
};

/// Errors that can occur during protobuf decoding
pub const DecodeError = error{
    /// Reached end of data unexpectedly
    UnexpectedEndOfData,
    /// Varint encoding is malformed (too many bytes)
    MalformedVarint,
    /// Unknown or unsupported wire type
    InvalidWireType,
    /// Field number is invalid (0 is reserved)
    InvalidFieldNumber,
    /// Nested message depth exceeded safety limit
    MaxDepthExceeded,
    /// Memory allocation failed
    OutOfMemory,
};

/// Field header containing field number and wire type
pub const FieldHeader = struct {
    field_num: u32,
    wire_type: WireType,
};

/// Protobuf wire format decoder.
///
/// Reads protobuf-encoded data from a byte slice, tracking position
/// and providing methods to decode various wire format types.
pub const ProtoDecoder = struct {
    data: []const u8,
    pos: usize,

    const Self = @This();

    /// Create a new decoder for the given data.
    pub fn init(data: []const u8) Self {
        return .{ .data = data, .pos = 0 };
    }

    /// Check if there is more data to read.
    pub fn hasMore(self: Self) bool {
        return self.pos < self.data.len;
    }

    /// Get remaining unread bytes.
    pub fn remaining(self: Self) usize {
        return self.data.len - self.pos;
    }

    /// Read a varint-encoded unsigned integer.
    ///
    /// Varints use 7 bits per byte with the MSB indicating continuation.
    pub fn readVarint(self: *Self) DecodeError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            // Add lower 7 bits to result
            result |= @as(u64, byte & 0x7F) << shift;

            // If MSB is 0, this is the last byte
            if (byte & 0x80 == 0) {
                return result;
            }

            shift += 7;

            // Varint can be at most 10 bytes (for 64-bit values)
            if (shift >= 70) {
                return DecodeError.MalformedVarint;
            }
        }

        return DecodeError.UnexpectedEndOfData;
    }

    /// Read a signed varint using ZigZag encoding.
    ///
    /// ZigZag maps signed integers to unsigned: 0->0, -1->1, 1->2, -2->3, etc.
    pub fn readSignedVarint(self: *Self) DecodeError!i64 {
        const n = try self.readVarint();
        // ZigZag decode: (n >> 1) ^ -(n & 1)
        return @as(i64, @bitCast(n >> 1)) ^ -@as(i64, @intCast(n & 1));
    }

    /// Read a field header (tag).
    ///
    /// The tag is a varint where lower 3 bits are wire type and upper bits are field number.
    pub fn readFieldHeader(self: *Self) DecodeError!FieldHeader {
        const tag = try self.readVarint();

        const wire_type_int: u3 = @truncate(tag);
        const field_num: u32 = @intCast(tag >> 3);

        if (field_num == 0) {
            return DecodeError.InvalidFieldNumber;
        }

        return .{
            .field_num = field_num,
            .wire_type = @enumFromInt(wire_type_int),
        };
    }

    /// Read a length-delimited field (string, bytes, embedded message).
    ///
    /// Returns a slice into the original data without copying.
    pub fn readBytes(self: *Self) DecodeError![]const u8 {
        const len = try self.readVarint();
        const len_usize: usize = @intCast(len);

        if (self.pos + len_usize > self.data.len) {
            return DecodeError.UnexpectedEndOfData;
        }

        const result = self.data[self.pos..][0..len_usize];
        self.pos += len_usize;
        return result;
    }

    /// Read a fixed 64-bit value (little-endian).
    pub fn readFixed64(self: *Self) DecodeError!u64 {
        if (self.pos + 8 > self.data.len) {
            return DecodeError.UnexpectedEndOfData;
        }

        const result = std.mem.readInt(u64, self.data[self.pos..][0..8], .little);
        self.pos += 8;
        return result;
    }

    /// Read a fixed 32-bit value (little-endian).
    pub fn readFixed32(self: *Self) DecodeError!u32 {
        if (self.pos + 4 > self.data.len) {
            return DecodeError.UnexpectedEndOfData;
        }

        const result = std.mem.readInt(u32, self.data[self.pos..][0..4], .little);
        self.pos += 4;
        return result;
    }

    /// Read a double (64-bit IEEE 754 float, little-endian).
    pub fn readDouble(self: *Self) DecodeError!f64 {
        const bits = try self.readFixed64();
        return @bitCast(bits);
    }

    /// Read a float (32-bit IEEE 754 float, little-endian).
    pub fn readFloat(self: *Self) DecodeError!f32 {
        const bits = try self.readFixed32();
        return @bitCast(bits);
    }

    /// Skip a field based on its wire type.
    ///
    /// Useful for ignoring unknown fields while preserving forward compatibility.
    pub fn skipField(self: *Self, wire_type: WireType) DecodeError!void {
        switch (wire_type) {
            .varint => _ = try self.readVarint(),
            .fixed64 => {
                if (self.pos + 8 > self.data.len) return DecodeError.UnexpectedEndOfData;
                self.pos += 8;
            },
            .length_delimited => _ = try self.readBytes(),
            .fixed32 => {
                if (self.pos + 4 > self.data.len) return DecodeError.UnexpectedEndOfData;
                self.pos += 4;
            },
            .start_group, .end_group => {
                // Groups are deprecated; skip by reading until end_group
                return DecodeError.InvalidWireType;
            },
        }
    }

    /// Create a sub-decoder for an embedded message.
    ///
    /// First reads the length-delimited bytes, then returns a new decoder
    /// positioned at the start of the embedded message.
    pub fn readEmbeddedMessage(self: *Self) DecodeError!Self {
        const bytes = try self.readBytes();
        return Self.init(bytes);
    }

    /// Read a packed repeated field of varints.
    pub fn readPackedVarints(self: *Self, allocator: std.mem.Allocator) DecodeError![]u64 {
        const bytes = try self.readBytes();
        var sub = Self.init(bytes);

        var list = std.ArrayListUnmanaged(u64){};
        errdefer list.deinit(allocator);

        while (sub.hasMore()) {
            const val = try sub.readVarint();
            list.append(allocator, val) catch return DecodeError.OutOfMemory;
        }

        return list.toOwnedSlice(allocator) catch return DecodeError.OutOfMemory;
    }

    /// Read a packed repeated field of fixed64 values.
    pub fn readPackedFixed64(self: *Self, allocator: std.mem.Allocator) DecodeError![]u64 {
        const bytes = try self.readBytes();

        if (bytes.len % 8 != 0) {
            return DecodeError.UnexpectedEndOfData;
        }

        const count = bytes.len / 8;
        var result = allocator.alloc(u64, count) catch return DecodeError.OutOfMemory;

        for (0..count) |i| {
            result[i] = std.mem.readInt(u64, bytes[i * 8 ..][0..8], .little);
        }

        return result;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "read varint single byte" {
    var decoder = ProtoDecoder.init(&[_]u8{0x01});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 1), val);
}

test "read varint 150" {
    // 150 = 0b10010110 = 0x96 01
    var decoder = ProtoDecoder.init(&[_]u8{ 0x96, 0x01 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 150), val);
}

test "read varint max single byte" {
    var decoder = ProtoDecoder.init(&[_]u8{0x7F});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 127), val);
}

test "read varint large value" {
    // 300 = 0b100101100 = 0xAC 0x02
    var decoder = ProtoDecoder.init(&[_]u8{ 0xAC, 0x02 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 300), val);
}

test "read signed varint positive" {
    // ZigZag: 1 -> 2 -> 0x02
    var decoder = ProtoDecoder.init(&[_]u8{0x02});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, 1), val);
}

test "read signed varint negative" {
    // ZigZag: -1 -> 1 -> 0x01
    var decoder = ProtoDecoder.init(&[_]u8{0x01});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, -1), val);
}

test "read field header" {
    // Field 1, wire type 0 (varint): (1 << 3) | 0 = 0x08
    var decoder = ProtoDecoder.init(&[_]u8{0x08});
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 1), header.field_num);
    try std.testing.expectEqual(WireType.varint, header.wire_type);
}

test "read field header larger field number" {
    // Field 16, wire type 2 (length-delimited): (16 << 3) | 2 = 0x82 0x01
    var decoder = ProtoDecoder.init(&[_]u8{ 0x82, 0x01 });
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 16), header.field_num);
    try std.testing.expectEqual(WireType.length_delimited, header.wire_type);
}

test "read bytes" {
    // Length 5, then "hello"
    var decoder = ProtoDecoder.init(&[_]u8{ 0x05, 'h', 'e', 'l', 'l', 'o' });
    const bytes = try decoder.readBytes();
    try std.testing.expectEqualStrings("hello", bytes);
}

test "read fixed64" {
    var data: [8]u8 = undefined;
    std.mem.writeInt(u64, &data, 0x123456789ABCDEF0, .little);
    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readFixed64();
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), val);
}

test "read fixed32" {
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, &data, 0x12345678, .little);
    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readFixed32();
    try std.testing.expectEqual(@as(u32, 0x12345678), val);
}

test "skip field varint" {
    var decoder = ProtoDecoder.init(&[_]u8{ 0x96, 0x01, 0xFF });
    try decoder.skipField(.varint);
    try std.testing.expectEqual(@as(usize, 2), decoder.pos);
}

test "skip field length_delimited" {
    var decoder = ProtoDecoder.init(&[_]u8{ 0x03, 'a', 'b', 'c', 0xFF });
    try decoder.skipField(.length_delimited);
    try std.testing.expectEqual(@as(usize, 4), decoder.pos);
}

test "unexpected end of data" {
    var decoder = ProtoDecoder.init(&[_]u8{0x80}); // Incomplete varint
    const result = decoder.readVarint();
    try std.testing.expectError(DecodeError.UnexpectedEndOfData, result);
}

test "embedded message" {
    // Embedded message: length 2, then two bytes
    var decoder = ProtoDecoder.init(&[_]u8{ 0x02, 0x08, 0x01 });
    var sub = try decoder.readEmbeddedMessage();

    const header = try sub.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 1), header.field_num);

    const val = try sub.readVarint();
    try std.testing.expectEqual(@as(u64, 1), val);
}

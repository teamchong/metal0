//! Protobuf decoder tests.
//!
//! Tests for the hand-rolled protobuf wire format decoder.

const std = @import("std");
const proto = @import("lanceql.proto");

const ProtoDecoder = proto.ProtoDecoder;
const WireType = proto.WireType;
const DecodeError = proto.DecodeError;

// ============================================================================
// Varint Tests
// ============================================================================

test "decode varint 0" {
    var decoder = ProtoDecoder.init(&[_]u8{0x00});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 0), val);
}

test "decode varint 1" {
    var decoder = ProtoDecoder.init(&[_]u8{0x01});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 1), val);
}

test "decode varint 127" {
    var decoder = ProtoDecoder.init(&[_]u8{0x7F});
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 127), val);
}

test "decode varint 128" {
    // 128 = 0x80 0x01
    var decoder = ProtoDecoder.init(&[_]u8{ 0x80, 0x01 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 128), val);
}

test "decode varint 300" {
    // 300 = 0xAC 0x02
    var decoder = ProtoDecoder.init(&[_]u8{ 0xAC, 0x02 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 300), val);
}

test "decode varint large" {
    // 16384 = 0x80 0x80 0x01
    var decoder = ProtoDecoder.init(&[_]u8{ 0x80, 0x80, 0x01 });
    const val = try decoder.readVarint();
    try std.testing.expectEqual(@as(u64, 16384), val);
}

test "decode signed varint 0" {
    var decoder = ProtoDecoder.init(&[_]u8{0x00});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, 0), val);
}

test "decode signed varint -1" {
    // ZigZag: -1 -> 1 -> 0x01
    var decoder = ProtoDecoder.init(&[_]u8{0x01});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, -1), val);
}

test "decode signed varint 1" {
    // ZigZag: 1 -> 2 -> 0x02
    var decoder = ProtoDecoder.init(&[_]u8{0x02});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, 1), val);
}

test "decode signed varint -2" {
    // ZigZag: -2 -> 3 -> 0x03
    var decoder = ProtoDecoder.init(&[_]u8{0x03});
    const val = try decoder.readSignedVarint();
    try std.testing.expectEqual(@as(i64, -2), val);
}

// ============================================================================
// Field Header Tests
// ============================================================================

test "decode field header field 1 varint" {
    // Field 1, wire type 0: (1 << 3) | 0 = 0x08
    var decoder = ProtoDecoder.init(&[_]u8{0x08});
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 1), header.field_num);
    try std.testing.expectEqual(WireType.varint, header.wire_type);
}

test "decode field header field 2 length_delimited" {
    // Field 2, wire type 2: (2 << 3) | 2 = 0x12
    var decoder = ProtoDecoder.init(&[_]u8{0x12});
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 2), header.field_num);
    try std.testing.expectEqual(WireType.length_delimited, header.wire_type);
}

test "decode field header field 15 fixed64" {
    // Field 15, wire type 1: (15 << 3) | 1 = 0x79
    var decoder = ProtoDecoder.init(&[_]u8{0x79});
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 15), header.field_num);
    try std.testing.expectEqual(WireType.fixed64, header.wire_type);
}

test "decode field header field 16" {
    // Field 16, wire type 0: (16 << 3) | 0 = 0x80 0x01
    var decoder = ProtoDecoder.init(&[_]u8{ 0x80, 0x01 });
    const header = try decoder.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 16), header.field_num);
    try std.testing.expectEqual(WireType.varint, header.wire_type);
}

// ============================================================================
// Length-Delimited Tests
// ============================================================================

test "decode bytes empty" {
    var decoder = ProtoDecoder.init(&[_]u8{0x00});
    const bytes = try decoder.readBytes();
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
}

test "decode bytes hello" {
    var decoder = ProtoDecoder.init(&[_]u8{ 0x05, 'h', 'e', 'l', 'l', 'o' });
    const bytes = try decoder.readBytes();
    try std.testing.expectEqualStrings("hello", bytes);
}

test "decode bytes with continuation" {
    // Length 150 (0x96 0x01) followed by data
    var data: [152]u8 = undefined;
    data[0] = 0x96;
    data[1] = 0x01;
    @memset(data[2..], 'x');

    var decoder = ProtoDecoder.init(&data);
    const bytes = try decoder.readBytes();
    try std.testing.expectEqual(@as(usize, 150), bytes.len);
}

// ============================================================================
// Fixed Width Tests
// ============================================================================

test "decode fixed64" {
    var data: [8]u8 = undefined;
    std.mem.writeInt(u64, &data, 0x123456789ABCDEF0, .little);

    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readFixed64();
    try std.testing.expectEqual(@as(u64, 0x123456789ABCDEF0), val);
}

test "decode fixed32" {
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, &data, 0x12345678, .little);

    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readFixed32();
    try std.testing.expectEqual(@as(u32, 0x12345678), val);
}

test "decode double" {
    const expected: f64 = 3.141592653589793;
    var data: [8]u8 = undefined;
    std.mem.writeInt(u64, &data, @bitCast(expected), .little);

    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readDouble();
    try std.testing.expectApproxEqRel(expected, val, 1e-15);
}

test "decode float" {
    const expected: f32 = 3.14159;
    var data: [4]u8 = undefined;
    std.mem.writeInt(u32, &data, @bitCast(expected), .little);

    var decoder = ProtoDecoder.init(&data);
    const val = try decoder.readFloat();
    try std.testing.expectApproxEqRel(expected, val, 1e-5);
}

// ============================================================================
// Error Cases
// ============================================================================

test "varint truncated" {
    // Continuation bit set but no more data
    var decoder = ProtoDecoder.init(&[_]u8{0x80});
    const result = decoder.readVarint();
    try std.testing.expectError(DecodeError.UnexpectedEndOfData, result);
}

test "bytes truncated" {
    // Length says 10, but only 5 bytes present
    var decoder = ProtoDecoder.init(&[_]u8{ 0x0A, 'a', 'b', 'c', 'd', 'e' });
    const result = decoder.readBytes();
    try std.testing.expectError(DecodeError.UnexpectedEndOfData, result);
}

test "fixed64 truncated" {
    var decoder = ProtoDecoder.init(&[_]u8{ 0x01, 0x02, 0x03, 0x04 });
    const result = decoder.readFixed64();
    try std.testing.expectError(DecodeError.UnexpectedEndOfData, result);
}

test "field number zero" {
    // Field 0 is reserved and invalid
    var decoder = ProtoDecoder.init(&[_]u8{0x00});
    const result = decoder.readFieldHeader();
    try std.testing.expectError(DecodeError.InvalidFieldNumber, result);
}

// ============================================================================
// Skip Field Tests
// ============================================================================

test "skip varint field" {
    // Varint 300 = 0xAC 0x02, then extra byte
    var decoder = ProtoDecoder.init(&[_]u8{ 0xAC, 0x02, 0xFF });
    try decoder.skipField(.varint);
    try std.testing.expectEqual(@as(usize, 2), decoder.pos);
}

test "skip length_delimited field" {
    // Length 3, then "abc", then extra byte
    var decoder = ProtoDecoder.init(&[_]u8{ 0x03, 'a', 'b', 'c', 0xFF });
    try decoder.skipField(.length_delimited);
    try std.testing.expectEqual(@as(usize, 4), decoder.pos);
}

test "skip fixed64 field" {
    var data: [10]u8 = undefined;
    @memset(&data, 0xAB);

    var decoder = ProtoDecoder.init(&data);
    try decoder.skipField(.fixed64);
    try std.testing.expectEqual(@as(usize, 8), decoder.pos);
}

test "skip fixed32 field" {
    var data: [6]u8 = undefined;
    @memset(&data, 0xAB);

    var decoder = ProtoDecoder.init(&data);
    try decoder.skipField(.fixed32);
    try std.testing.expectEqual(@as(usize, 4), decoder.pos);
}

// ============================================================================
// Embedded Message Tests
// ============================================================================

test "embedded message" {
    // Outer message: field 1 (embedded), length 3
    // Inner message: field 1 (varint) = 150
    var decoder = ProtoDecoder.init(&[_]u8{
        0x03, // length 3
        0x08, // field 1, varint
        0x96,
        0x01, // 150
    });

    var sub = try decoder.readEmbeddedMessage();
    const header = try sub.readFieldHeader();
    try std.testing.expectEqual(@as(u32, 1), header.field_num);

    const val = try sub.readVarint();
    try std.testing.expectEqual(@as(u64, 150), val);
}

// ============================================================================
// hasMore and remaining Tests
// ============================================================================

test "hasMore and remaining" {
    var decoder = ProtoDecoder.init(&[_]u8{ 0x01, 0x02, 0x03 });

    try std.testing.expect(decoder.hasMore());
    try std.testing.expectEqual(@as(usize, 3), decoder.remaining());

    _ = try decoder.readVarint();
    try std.testing.expect(decoder.hasMore());
    try std.testing.expectEqual(@as(usize, 2), decoder.remaining());

    _ = try decoder.readVarint();
    _ = try decoder.readVarint();
    try std.testing.expect(!decoder.hasMore());
    try std.testing.expectEqual(@as(usize, 0), decoder.remaining());
}

// ============================================================================
// Packed Repeated Tests
// ============================================================================

test "packed varints" {
    const allocator = std.testing.allocator;

    // Length 3, then varints: 1, 2, 3
    var decoder = ProtoDecoder.init(&[_]u8{ 0x03, 0x01, 0x02, 0x03 });
    const values = try decoder.readPackedVarints(allocator);
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 3), values.len);
    try std.testing.expectEqual(@as(u64, 1), values[0]);
    try std.testing.expectEqual(@as(u64, 2), values[1]);
    try std.testing.expectEqual(@as(u64, 3), values[2]);
}

test "packed fixed64" {
    const allocator = std.testing.allocator;

    // Length 16, then two u64 values
    var data: [17]u8 = undefined;
    data[0] = 16; // length
    std.mem.writeInt(u64, data[1..9], 100, .little);
    std.mem.writeInt(u64, data[9..17], 200, .little);

    var decoder = ProtoDecoder.init(&data);
    const values = try decoder.readPackedFixed64(allocator);
    defer allocator.free(values);

    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(@as(u64, 100), values[0]);
    try std.testing.expectEqual(@as(u64, 200), values[1]);
}

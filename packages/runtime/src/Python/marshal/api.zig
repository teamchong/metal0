/// marshal/api - High-level API for marshalling
/// Mirrors cpython/Python/marshal.c public API

const std = @import("std");
const types = @import("types.zig");
const writer_mod = @import("writer.zig");
const reader_mod = @import("reader.zig");

pub const Value = types.Value;
pub const Writer = writer_mod.Writer;
pub const Reader = reader_mod.Reader;

// ============================================================================
// Convenience Functions
// ============================================================================

/// Marshal data to bytes
pub fn dumps(allocator: std.mem.Allocator, value: Value) ![]u8 {
    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer_mod.writeValue(&writer, value);

    return allocator.dupe(u8, writer.getData());
}

/// Unmarshal bytes to value
pub fn loads(allocator: std.mem.Allocator, data: []const u8) !Value {
    var reader = Reader.init(allocator, data);
    defer reader.deinit();

    return reader_mod.readValue(&reader);
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize marshal module
pub fn init() void {
    // Nothing to initialize
}

/// Finalize marshal module
pub fn fini() void {
    // Nothing to finalize
}

// ============================================================================
// Tests
// ============================================================================

test "marshal none" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value.none);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 1), data.len);
    try std.testing.expectEqual(@as(u8, 'N'), data[0]);
}

test "marshal bool" {
    const allocator = std.testing.allocator;

    const data_true = try dumps(allocator, Value.true_);
    defer allocator.free(data_true);
    try std.testing.expectEqual(@as(u8, 'T'), data_true[0]);

    const data_false = try dumps(allocator, Value.false_);
    defer allocator.free(data_false);
    try std.testing.expectEqual(@as(u8, 'F'), data_false[0]);
}

test "marshal int" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value{ .int_ = 42 });
    defer allocator.free(data);

    try std.testing.expectEqual(@as(u8, 'i'), data[0]);

    const value = try loads(allocator, data);
    try std.testing.expectEqual(@as(i64, 42), value.int_);
}

test "marshal string" {
    const allocator = std.testing.allocator;

    const data = try dumps(allocator, Value{ .string = "hello" });
    defer allocator.free(data);

    const value = try loads(allocator, data);
    try std.testing.expectEqualStrings("hello", value.string);
}

test "marshal tuple" {
    const allocator = std.testing.allocator;

    var items = [_]Value{
        Value{ .int_ = 1 },
        Value{ .int_ = 2 },
        Value{ .int_ = 3 },
    };

    const data = try dumps(allocator, Value{ .tuple = &items });
    defer allocator.free(data);

    const value = try loads(allocator, data);
    defer allocator.free(value.tuple);

    try std.testing.expectEqual(@as(usize, 3), value.tuple.len);
    try std.testing.expectEqual(@as(i64, 1), value.tuple[0].int_);
    try std.testing.expectEqual(@as(i64, 2), value.tuple[1].int_);
    try std.testing.expectEqual(@as(i64, 3), value.tuple[2].int_);
}

test "writer reader" {
    const allocator = std.testing.allocator;

    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeByte(0x42);
    try writer.writeInt32(12345);
    try writer.writeFloat64(3.14159);

    const data = writer.getData();

    var reader = Reader.init(allocator, data);
    defer reader.deinit();

    try std.testing.expectEqual(@as(u8, 0x42), try reader.readByte());
    try std.testing.expectEqual(@as(i32, 12345), try reader.readInt32());
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), try reader.readFloat64(), 0.00001);
}

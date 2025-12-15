/// List operations for reducing monomorphization explosion
/// Extracts type casting logic from inline list literal generation
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Cast any value to target list element type
/// Compiled ONCE per (SrcType, DstType) pair, not per list literal
/// This eliminates the O(n²) monomorphization from inline type checks
pub fn castToListElement(comptime DstType: type, comptime SrcType: type, value: SrcType, allocator: std.mem.Allocator) !DstType {
    // Same type - no cast needed
    if (SrcType == DstType) return value;

    // PyValue conversion
    if (DstType == PyValue) {
        return try PyValue.fromAlloc(allocator, value);
    }

    // Int to float
    if (DstType == f64 and (SrcType == i64 or SrcType == comptime_int)) {
        return @as(f64, @floatFromInt(value));
    }

    // Comptime float to f64
    if (DstType == f64 and SrcType == comptime_float) {
        return @as(f64, value);
    }

    // Array to slice coercion
    if (@typeInfo(DstType) == .pointer and @typeInfo(DstType).pointer.size == .slice) {
        if (@typeInfo(SrcType) == .array) {
            return &value;
        }
    }

    // Fallback - identity (let Zig handle or fail at compile time)
    return value;
}

/// Append value to list with type casting
/// Single function call instead of inline type-checking block
pub fn appendCast(comptime T: type, list: *std.ArrayListUnmanaged(T), allocator: std.mem.Allocator, value: anytype) !void {
    const cast_val = try castToListElement(T, @TypeOf(value), value, allocator);
    try list.append(allocator, cast_val);
}

test "castToListElement - same type" {
    const val: i64 = 42;
    const result = try castToListElement(i64, i64, val, std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 42), result);
}

test "castToListElement - int to float" {
    const val: i64 = 42;
    const result = try castToListElement(f64, i64, val, std.testing.allocator);
    try std.testing.expectEqual(@as(f64, 42.0), result);
}

test "appendCast - basic" {
    var list: std.ArrayListUnmanaged(i64) = .{};
    defer list.deinit(std.testing.allocator);

    try appendCast(i64, &list, std.testing.allocator, @as(i64, 1));
    try appendCast(i64, &list, std.testing.allocator, @as(i64, 2));
    try appendCast(i64, &list, std.testing.allocator, @as(i64, 3));

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(i64, 1), list.items[0]);
    try std.testing.expectEqual(@as(i64, 2), list.items[1]);
    try std.testing.expectEqual(@as(i64, 3), list.items[2]);
}

test "appendCast - mixed int and float to float list" {
    var list: std.ArrayListUnmanaged(f64) = .{};
    defer list.deinit(std.testing.allocator);

    try appendCast(f64, &list, std.testing.allocator, @as(i64, 1));
    try appendCast(f64, &list, std.testing.allocator, @as(f64, 2.5));

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqual(@as(f64, 1.0), list.items[0]);
    try std.testing.expectEqual(@as(f64, 2.5), list.items[1]);
}

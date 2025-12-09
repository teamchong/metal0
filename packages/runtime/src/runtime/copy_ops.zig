/// Copy operations runtime helpers
/// Extracted from codegen to prevent comptime explosion from @typeInfo/@TypeOf/@hasField checks
///
/// Problem: Each copy.copy() and copy.deepcopy() call generated inline blocks with
/// multiple @typeInfo/@TypeOf/@hasField checks, causing O(n²) monomorphization.
///
/// Solution: These helpers are compiled once per type, called N times.
const std = @import("std");

pub const CopyError = error{
    OutOfMemory,
};

/// Shallow copy - copies the container but not the elements
/// For primitives: returns the value as-is
/// For ArrayList-like structs (with .items): creates new container with same items
pub fn shallowCopy(comptime T: type, allocator: std.mem.Allocator, src: T) CopyError!T {
    const type_info = @typeInfo(T);

    // Primitives - return as-is
    if (T == i64 or T == f64 or T == bool or T == []const u8) {
        return src;
    }

    // Structs with .items field (ArrayList-like)
    if (type_info == .@"struct" and @hasField(T, "items")) {
        var copy = T.init(allocator);
        copy.appendSlice(allocator, src.items) catch return CopyError.OutOfMemory;
        return copy;
    }

    // Other types - return as-is (shallow copy of value)
    return src;
}

/// Deep copy - copies the container AND the elements
/// For primitives: returns the value as-is
/// For ArrayList-like structs: creates new container with copied items
pub fn deepCopy(comptime T: type, allocator: std.mem.Allocator, src: T) CopyError!T {
    const type_info = @typeInfo(T);

    // Primitives - return as-is
    if (T == i64 or T == f64 or T == bool or T == []const u8) {
        return src;
    }

    // Structs with .items field (ArrayList-like)
    if (type_info == .@"struct" and @hasField(T, "items")) {
        var copy = T.init(allocator);
        for (src.items) |item| {
            copy.append(allocator, item) catch continue;
        }
        return copy;
    }

    // Other types - return as-is
    return src;
}

// Tests
test "shallowCopy primitives" {
    const allocator = std.testing.allocator;

    // i64
    const i = try shallowCopy(i64, allocator, 42);
    try std.testing.expectEqual(@as(i64, 42), i);

    // f64
    const f = try shallowCopy(f64, allocator, 3.14);
    try std.testing.expectEqual(@as(f64, 3.14), f);

    // bool
    const b = try shallowCopy(bool, allocator, true);
    try std.testing.expectEqual(true, b);
}

test "shallowCopy ArrayList" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(i64).init(allocator);
    defer list.deinit();
    try list.append(1);
    try list.append(2);
    try list.append(3);

    var copy = try shallowCopy(std.ArrayList(i64), allocator, list);
    defer copy.deinit();

    try std.testing.expectEqual(@as(usize, 3), copy.items.len);
    try std.testing.expectEqual(@as(i64, 1), copy.items[0]);
    try std.testing.expectEqual(@as(i64, 2), copy.items[1]);
    try std.testing.expectEqual(@as(i64, 3), copy.items[2]);

    // Verify it's a separate copy
    try list.append(4);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
    try std.testing.expectEqual(@as(usize, 3), copy.items.len);
}

test "deepCopy ArrayList" {
    const allocator = std.testing.allocator;

    var list = std.ArrayList(i64).init(allocator);
    defer list.deinit();
    try list.append(10);
    try list.append(20);

    var copy = try deepCopy(std.ArrayList(i64), allocator, list);
    defer copy.deinit();

    try std.testing.expectEqual(@as(usize, 2), copy.items.len);
    try std.testing.expectEqual(@as(i64, 10), copy.items[0]);
    try std.testing.expectEqual(@as(i64, 20), copy.items[1]);
}

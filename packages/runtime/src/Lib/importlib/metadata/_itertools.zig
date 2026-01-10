//! importlib.metadata._itertools - Iterator utilities
//! Reference: cpython/Lib/importlib/metadata/_itertools.py
//!
//! CPython exports: always_iterable, unique_everseen

const std = @import("std");

/// alwaysIterable - Ensure value is iterable
/// CPython: def always_iterable(obj)
pub fn alwaysIterable(comptime T: type, value: ?T) []const T {
    if (value) |v| {
        return &[_]T{v};
    }
    return &[_]T{};
}

/// uniqueEverseen - Yield unique elements preserving order
/// CPython: def unique_everseen(iterable, key=None)
pub fn uniqueEverseen(comptime T: type, allocator: std.mem.Allocator, items: []const T) !std.ArrayList(T) {
    var seen = std.AutoHashMap(T, void).init(allocator);
    defer seen.deinit();

    var result = std.ArrayList(T){};
    for (items) |item| {
        if (!seen.contains(item)) {
            try seen.put(item, {});
            try result.append(allocator, item);
        }
    }
    return result;
}

test "uniqueEverseen" {
    const allocator = std.testing.allocator;
    const items = [_]i32{ 1, 2, 1, 3, 2, 4 };
    var result = try uniqueEverseen(i32, allocator, &items);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), result.items.len);
    try std.testing.expectEqual(@as(i32, 1), result.items[0]);
    try std.testing.expectEqual(@as(i32, 2), result.items[1]);
    try std.testing.expectEqual(@as(i32, 3), result.items[2]);
    try std.testing.expectEqual(@as(i32, 4), result.items[3]);
}

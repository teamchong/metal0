//! importlib.resources._itertools - Iterator utilities
//! Reference: cpython/Lib/importlib/resources/_itertools.py

const std = @import("std");

/// Only yield unique elements, preserving order
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
}

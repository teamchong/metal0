//! UserList - Wrapper around list for easier subclassing
//!
//! Mirrors: CPython Lib/collections/__init__.py - UserList

const std = @import("std");

/// Wrapper around list for easier subclassing
pub fn UserList(comptime T: type) type {
    return struct {
        const Self = @This();
        data: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .data = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn append(self: *Self, item: T) !void {
            try self.data.append(item);
        }

        pub fn get(self: Self, index: usize) ?T {
            if (index < self.data.items.len) {
                return self.data.items[index];
            }
            return null;
        }

        pub fn len(self: Self) usize {
            return self.data.items.len;
        }

        pub fn pop(self: *Self) ?T {
            return self.data.popOrNull();
        }
    };
}

test "UserList" {
    const allocator = std.testing.allocator;

    var ul = UserList(i32).init(allocator);
    defer ul.deinit();

    try ul.append(1);
    try ul.append(2);

    try std.testing.expectEqual(@as(usize, 2), ul.len());
    try std.testing.expectEqual(@as(i32, 1), ul.get(0).?);
}

//! UserString - Wrapper around string for easier subclassing
//!
//! Mirrors: CPython Lib/collections/__init__.py - UserString

const std = @import("std");

/// Wrapper around string for easier subclassing
pub const UserString = struct {
    data: []const u8,

    pub fn init(s: []const u8) UserString {
        return .{ .data = s };
    }

    pub fn len(self: UserString) usize {
        return self.data.len;
    }

    pub fn str(self: UserString) []const u8 {
        return self.data;
    }
};

test "UserString" {
    const us = UserString.init("hello");
    try std.testing.expectEqual(@as(usize, 5), us.len());
    try std.testing.expectEqualStrings("hello", us.str());
}

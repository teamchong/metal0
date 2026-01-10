//! test.test_ctypes.test_strings - Tests for ctypes string handling
//! Reference: cpython/Lib/test/test_ctypes/test_strings.py

const std = @import("std");
const _support = @import("_support.zig");

pub const c_char_p = struct {
    ptr: ?[*:0]const u8 = null,

    pub fn init(s: ?[*:0]const u8) @This() { return .{ .ptr = s }; }

    pub fn value(self: @This()) ?[]const u8 {
        if (self.ptr) |p| return std.mem.span(p);
        return null;
    }

    pub fn isNull(self: @This()) bool { return self.ptr == null; }
    pub fn len(self: @This()) usize {
        if (self.ptr) |p| return std.mem.len(p);
        return 0;
    }
};

pub fn StringBuffer(comptime N: usize) type {
    return struct {
        const Self = @This();
        data: [N]u8 = undefined,
        _len: usize = 0,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn fromString(s: []const u8) Self {
            var self = Self.init();
            const copy_len = @min(s.len, N - 1);
            @memcpy(self.data[0..copy_len], s[0..copy_len]);
            self._len = copy_len;
            return self;
        }

        pub fn value(self: *const Self) []const u8 { return self.data[0..self._len]; }
        pub fn set(self: *Self, s: []const u8) void {
            @memset(&self.data, 0);
            const copy_len = @min(s.len, N - 1);
            @memcpy(self.data[0..copy_len], s[0..copy_len]);
            self._len = copy_len;
        }
    };
}

pub fn create_string_buffer(comptime size: usize) StringBuffer(size) {
    return StringBuffer(size).init();
}

test "c_char_p" {
    const str = "Hello";
    const cp = c_char_p.init(str.ptr);
    try std.testing.expect(!cp.isNull());
}

test "string_buffer" {
    var buf = create_string_buffer(100);
    buf.set("Test");
    try std.testing.expectEqualStrings("Test", buf.value());
}

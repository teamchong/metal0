//! test.test_ctypes.test_stringptr - Tests for ctypes string pointers
//! Reference: cpython/Lib/test/test_ctypes/test_stringptr.py

const std = @import("std");

pub const c_char_p = struct {
    ptr: ?[*:0]const u8 = null,
    pub fn init(s: ?[*:0]const u8) @This() { return .{ .ptr = s }; }
    pub fn value(self: @This()) ?[]const u8 {
        if (self.ptr) |p| return std.mem.span(p);
        return null;
    }
};

pub const c_wchar_p = struct {
    ptr: ?[*:0]const u16 = null,
    pub fn init(s: ?[*:0]const u16) @This() { return .{ .ptr = s }; }
};

test "c_char_p" {
    const s = "Hello";
    const p = c_char_p.init(s.ptr);
    if (p.value()) |v| try std.testing.expectEqualStrings("Hello", v);
}

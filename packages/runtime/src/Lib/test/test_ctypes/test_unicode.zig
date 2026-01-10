//! test.test_ctypes.test_unicode - Tests for ctypes unicode handling
//! Reference: cpython/Lib/test/test_ctypes/test_unicode.py

const std = @import("std");

pub const c_wchar = u16;
pub const c_wchar_p = ?[*:0]const u16;

pub fn WCharArray(comptime N: usize) type {
    return struct {
        data: [N]u16 = undefined,
        pub fn init() @This() { var self = @This(){}; @memset(&self.data, 0); return self; }
        pub fn fromAscii(s: []const u8) @This() {
            var self = @This().init();
            for (s, 0..) |c, i| { if (i >= N - 1) break; self.data[i] = c; }
            return self;
        }
    };
}

test "wchar_array" {
    const arr = WCharArray(10).fromAscii("Hello");
    try std.testing.expectEqual(@as(u16, 'H'), arr.data[0]);
}

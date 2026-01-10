//! test.test_ctypes.test_win32 - Windows-specific ctypes tests
//! Reference: cpython/Lib/test/test_ctypes/test_win32.py

const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;

pub const BOOL = i32;
pub const DWORD = u32;
pub const HANDLE = ?*anyopaque;
pub const HWND = ?*anyopaque;
pub const HMODULE = ?*anyopaque;
pub const LPSTR = ?[*:0]u8;
pub const LPCSTR = ?[*:0]const u8;

pub const WinDLL = struct {
    name: []const u8,
    handle: HMODULE = null,
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
};

pub const OleDLL = WinDLL;

test "win32_types" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(BOOL));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(DWORD));
}

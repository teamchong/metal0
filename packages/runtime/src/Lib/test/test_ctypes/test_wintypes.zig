//! test.test_ctypes.test_wintypes - Tests for Windows types
//! Reference: cpython/Lib/test/test_ctypes/test_wintypes.py

const std = @import("std");

pub const BYTE = u8;
pub const WORD = u16;
pub const DWORD = u32;
pub const QWORD = u64;
pub const BOOL = i32;
pub const BOOLEAN = u8;
pub const CHAR = u8;
pub const WCHAR = u16;
pub const SHORT = i16;
pub const USHORT = u16;
pub const INT = i32;
pub const UINT = u32;
pub const LONG = i32;
pub const ULONG = u32;
pub const LONGLONG = i64;
pub const ULONGLONG = u64;
pub const FLOAT = f32;
pub const DOUBLE = f64;
pub const HANDLE = ?*anyopaque;
pub const HWND = HANDLE;
pub const HDC = HANDLE;
pub const HMODULE = HANDLE;
pub const HINSTANCE = HANDLE;
pub const LPVOID = ?*anyopaque;
pub const LPCVOID = ?*const anyopaque;
pub const LPSTR = ?[*:0]u8;
pub const LPCSTR = ?[*:0]const u8;
pub const LPWSTR = ?[*:0]u16;
pub const LPCWSTR = ?[*:0]const u16;

pub const POINT = struct { x: LONG = 0, y: LONG = 0 };
pub const RECT = struct { left: LONG = 0, top: LONG = 0, right: LONG = 0, bottom: LONG = 0 };
pub const SIZE = struct { cx: LONG = 0, cy: LONG = 0 };

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

test "wintypes_sizes" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(BYTE));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(WORD));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(DWORD));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(QWORD));
}

test "point_struct" {
    const p = POINT{ .x = 10, .y = 20 };
    try std.testing.expectEqual(@as(LONG, 10), p.x);
}

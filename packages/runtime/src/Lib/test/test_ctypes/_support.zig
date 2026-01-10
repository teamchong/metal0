//! test.test_ctypes._support - Support utilities for ctypes tests
//! Reference: cpython/Lib/test/test_ctypes/_support.py

const std = @import("std");

// ============================================================================
// C Type Definitions
// ============================================================================

pub const c_short = i16;
pub const c_ushort = u16;
pub const c_int = i32;
pub const c_uint = u32;
pub const c_long = i64;
pub const c_ulong = u64;
pub const c_longlong = i64;
pub const c_ulonglong = u64;
pub const c_float = f32;
pub const c_double = f64;
pub const c_char = i8;
pub const c_uchar = u8;
pub const c_wchar = u16;
pub const c_void_p = ?*anyopaque;
pub const c_char_p = ?[*:0]const u8;
pub const c_size_t = usize;
pub const c_ssize_t = isize;

pub fn is_windows() bool { return @import("builtin").os.tag == .windows; }
pub fn is_macos() bool { return @import("builtin").os.tag == .macos; }
pub fn is_linux() bool { return @import("builtin").os.tag == .linux; }

pub fn get_libc_path() []const u8 {
    if (is_windows()) return "msvcrt.dll"
    else if (is_macos()) return "/usr/lib/libSystem.B.dylib"
    else return "libc.so.6";
}

pub fn POINTER(comptime T: type) type {
    return struct {
        const Self = @This();
        ptr: ?*T = null,
        pub fn init(p: ?*T) Self { return .{ .ptr = p }; }
        pub fn contents(self: Self) ?*T { return self.ptr; }
    };
}

pub fn Array(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        data: [N]T = undefined,
        pub fn init() Self { return .{}; }
    };
}

pub const CDLL = struct {
    name: []const u8,
    handle: ?*anyopaque = null,
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
};

test "c_types" {
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(c_int));
}

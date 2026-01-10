//! test.test_ctypes.test_pointers - Tests for ctypes pointers
//! Reference: cpython/Lib/test/test_ctypes/test_pointers.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn POINTER(comptime T: type) type {
    return struct {
        const Self = @This();
        const Pointee = T;
        ptr: ?*T = null,

        pub fn init(p: ?*T) Self { return .{ .ptr = p }; }
        pub fn contents(self: Self) ?T {
            if (self.ptr) |p| return p.*;
            return null;
        }
        pub fn isNull(self: Self) bool { return self.ptr == null; }
        pub fn setContents(self: Self, value: T) void {
            if (self.ptr) |p| p.* = value;
        }
    };
}

pub const c_void_p = ?*anyopaque;
pub const c_char_p = ?[*:0]const u8;
pub const IntPtr = POINTER(i32);
pub const DoublePtr = POINTER(f64);

pub fn pointer(value: anytype) POINTER(@TypeOf(value.*)) {
    return POINTER(@TypeOf(value.*)).init(value);
}

pub fn cast(comptime T: type, ptr: anytype) T {
    return @ptrCast(@alignCast(ptr));
}

test "pointer_init" {
    var value: i32 = 42;
    const ptr = IntPtr.init(&value);
    try std.testing.expectEqual(@as(?i32, 42), ptr.contents());
}

test "pointer_null" {
    const ptr = IntPtr.init(null);
    try std.testing.expect(ptr.isNull());
}

test "pointer_set" {
    var value: i32 = 10;
    const ptr = IntPtr.init(&value);
    ptr.setContents(20);
    try std.testing.expectEqual(@as(i32, 20), value);
}

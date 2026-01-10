//! test.test_ctypes.test_numbers - Tests for ctypes numeric types
//! Reference: cpython/Lib/test/test_ctypes/test_numbers.py

const std = @import("std");
const _support = @import("_support.zig");

pub const c_byte = i8;
pub const c_ubyte = u8;
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
pub const c_longdouble = f128;

pub fn Number(comptime T: type) type {
    return struct {
        const Self = @This();
        value: T = 0,

        pub fn init(v: T) Self { return .{ .value = v }; }
        pub fn get(self: Self) T { return self.value; }
        pub fn set(self: *Self, v: T) void { self.value = v; }
    };
}

pub const CInt = Number(c_int);
pub const CLong = Number(c_long);
pub const CDouble = Number(c_double);

test "c_int_size" { try std.testing.expectEqual(@as(usize, 4), @sizeOf(c_int)); }
test "c_long_size" { try std.testing.expectEqual(@as(usize, 8), @sizeOf(c_long)); }
test "c_double_size" { try std.testing.expectEqual(@as(usize, 8), @sizeOf(c_double)); }
test "number_wrapper" {
    var n = CInt.init(42);
    try std.testing.expectEqual(@as(c_int, 42), n.get());
    n.set(100);
    try std.testing.expectEqual(@as(c_int, 100), n.get());
}

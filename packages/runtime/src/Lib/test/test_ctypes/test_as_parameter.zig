//! test.test_ctypes.test_as_parameter - Tests for _as_parameter_ protocol
//! Reference: cpython/Lib/test/test_ctypes/test_as_parameter.py

const std = @import("std");

pub fn AsParameter(comptime T: type) type {
    return struct {
        const Self = @This();
        value: T,
        
        pub fn init(v: T) Self { return .{ .value = v }; }
        pub fn _as_parameter_(self: Self) T { return self.value; }
    };
}

pub const IntParam = AsParameter(i32);
pub const PtrParam = AsParameter(?*anyopaque);

test "as_parameter" {
    const p = IntParam.init(42);
    try std.testing.expectEqual(@as(i32, 42), p._as_parameter_());
}

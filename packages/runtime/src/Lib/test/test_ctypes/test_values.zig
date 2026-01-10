//! test.test_ctypes.test_values - Tests for ctypes value handling
//! Reference: cpython/Lib/test/test_ctypes/test_values.py

const std = @import("std");

pub fn Value(comptime T: type) type {
    return struct {
        const Self = @This();
        _value: T = std.mem.zeroes(T),
        
        pub fn init(v: T) Self { return .{ ._value = v }; }
        pub fn value(self: Self) T { return self._value; }
        pub fn setValue(self: *Self, v: T) void { self._value = v; }
    };
}

pub const IntValue = Value(i32);
pub const DoubleValue = Value(f64);

test "int_value" {
    var v = IntValue.init(42);
    try std.testing.expectEqual(@as(i32, 42), v.value());
    v.setValue(100);
    try std.testing.expectEqual(@as(i32, 100), v.value());
}

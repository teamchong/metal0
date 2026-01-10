//! test.test_ctypes.test_simplesubclasses - Tests for simple ctypes subclasses
//! Reference: cpython/Lib/test/test_ctypes/test_simplesubclasses.py

const std = @import("std");

pub fn SimpleType(comptime T: type) type {
    return struct {
        const Self = @This();
        value: T = std.mem.zeroes(T),
        pub fn init(v: T) Self { return .{ .value = v }; }
        pub fn get(self: Self) T { return self.value; }
    };
}

pub const MyInt = SimpleType(i32);
pub const MyDouble = SimpleType(f64);

test "simple_subclass" {
    const v = MyInt.init(42);
    try std.testing.expectEqual(@as(i32, 42), v.get());
}

//! test.test_ctypes.test_array_in_pointer - Tests for array pointers
//! Reference: cpython/Lib/test/test_ctypes/test_array_in_pointer.py

const std = @import("std");

pub fn ArrayPointer(comptime T: type, comptime N: usize) type {
    return struct {
        ptr: *[N]T,
        pub fn init(arr: *[N]T) @This() { return .{ .ptr = arr }; }
        pub fn get(self: @This(), i: usize) T { return self.ptr[i]; }
    };
}

test "array_in_pointer" {
    var arr = [_]i32{ 1, 2, 3 };
    const p = ArrayPointer(i32, 3).init(&arr);
    try std.testing.expectEqual(@as(i32, 1), p.get(0));
}

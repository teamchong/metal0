//! test.test_ctypes.test_slicing - Tests for ctypes array slicing
//! Reference: cpython/Lib/test/test_ctypes/test_slicing.py

const std = @import("std");

pub fn ArraySlice(comptime T: type) type {
    return struct {
        ptr: [*]T,
        len: usize,
        
        pub fn init(ptr: [*]T, len: usize) @This() { return .{ .ptr = ptr, .len = len }; }
        pub fn get(self: @This(), i: usize) ?T { return if (i < self.len) self.ptr[i] else null; }
        pub fn slice(self: @This(), start: usize, end: usize) ?@This() {
            if (start > end or end > self.len) return null;
            return .{ .ptr = self.ptr + start, .len = end - start };
        }
    };
}

test "array_slice" {
    var arr = [_]i32{ 1, 2, 3, 4, 5 };
    const s = ArraySlice(i32).init(&arr, 5);
    try std.testing.expectEqual(@as(?i32, 1), s.get(0));
    try std.testing.expectEqual(@as(?i32, 5), s.get(4));
}

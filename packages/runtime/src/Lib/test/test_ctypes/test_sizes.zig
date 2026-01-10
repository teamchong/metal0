//! test.test_ctypes.test_sizes - Tests for ctypes type sizes
//! Reference: cpython/Lib/test/test_ctypes/test_sizes.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn sizeof(comptime T: type) usize { return @sizeOf(T); }
pub fn alignmentof(comptime T: type) usize { return @alignOf(T); }

test "sizeof_basic" {
    try std.testing.expectEqual(@as(usize, 1), sizeof(i8));
    try std.testing.expectEqual(@as(usize, 2), sizeof(i16));
    try std.testing.expectEqual(@as(usize, 4), sizeof(i32));
    try std.testing.expectEqual(@as(usize, 8), sizeof(i64));
    try std.testing.expectEqual(@as(usize, 4), sizeof(f32));
    try std.testing.expectEqual(@as(usize, 8), sizeof(f64));
}

test "alignmentof_basic" {
    try std.testing.expect(alignmentof(i32) >= 4);
    try std.testing.expect(alignmentof(i64) >= 8);
}

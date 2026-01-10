//! test.test_ctypes.test_containment - Tests for structure containment
//! Reference: cpython/Lib/test/test_ctypes/test_containment.py

const std = @import("std");

pub const Inner = struct { value: i32 = 0 };
pub const Outer = struct {
    inner: Inner = .{},
    count: i32 = 0,
};

test "containment" {
    var o = Outer{ .inner = .{ .value = 42 }, .count = 1 };
    try std.testing.expectEqual(@as(i32, 42), o.inner.value);
    o.inner.value = 100;
    try std.testing.expectEqual(@as(i32, 100), o.inner.value);
}

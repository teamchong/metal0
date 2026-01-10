//! test.test_ctypes.test_anon - Tests for anonymous structures and unions
//! Reference: cpython/Lib/test/test_ctypes/test_anon.py

const std = @import("std");

pub const AnonStruct = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const AnonUnion = union {
    i: i32,
    f: f32,
};

test "anon_struct" {
    const s = AnonStruct{ .x = 1, .y = 2 };
    try std.testing.expectEqual(@as(i32, 1), s.x);
}

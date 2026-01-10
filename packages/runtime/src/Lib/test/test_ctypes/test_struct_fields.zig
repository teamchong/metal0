//! test.test_ctypes.test_struct_fields - Tests for ctypes structure fields
//! Reference: cpython/Lib/test/test_ctypes/test_struct_fields.py

const std = @import("std");

pub const FieldDescriptor = struct {
    name: []const u8,
    type_name: []const u8,
    offset: usize,
    size: usize,
};

pub fn getFields(comptime T: type) []const FieldDescriptor {
    _ = T;
    return &.{};
}

pub const TestStruct = struct {
    a: i32 = 0,
    b: i64 = 0,
    c: f64 = 0.0,
};

test "struct_fields" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(TestStruct, "a"));
}

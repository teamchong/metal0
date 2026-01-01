//! Type predicates for common type checks
//!
//! Centralizes repeated patterns like `info == .int or info == .comptime_int`
//! to avoid duplication across runtime files.

const std = @import("std");

/// Check if type info represents an integer type (int or comptime_int)
pub inline fn isIntInfo(comptime info: std.builtin.Type) bool {
    return info == .int or info == .comptime_int;
}

/// Check if type info represents a float type (float or comptime_float)
pub inline fn isFloatInfo(comptime info: std.builtin.Type) bool {
    return info == .float or info == .comptime_float;
}

/// Check if type info represents any numeric type (int, float, or comptime variants)
pub inline fn isNumericInfo(comptime info: std.builtin.Type) bool {
    return isIntInfo(info) or isFloatInfo(info);
}

/// Check if a type is an integer type
pub inline fn isInt(comptime T: type) bool {
    return isIntInfo(@typeInfo(T));
}

/// Check if a type is a float type
pub inline fn isFloat(comptime T: type) bool {
    return isFloatInfo(@typeInfo(T));
}

/// Check if a type is numeric (int or float)
pub inline fn isNumeric(comptime T: type) bool {
    return isNumericInfo(@typeInfo(T));
}

// Tests
test "isIntInfo" {
    try std.testing.expect(isIntInfo(@typeInfo(i32)));
    try std.testing.expect(isIntInfo(@typeInfo(u64)));
    try std.testing.expect(isIntInfo(@typeInfo(comptime_int)));
    try std.testing.expect(!isIntInfo(@typeInfo(f64)));
    try std.testing.expect(!isIntInfo(@typeInfo(bool)));
}

test "isFloatInfo" {
    try std.testing.expect(isFloatInfo(@typeInfo(f32)));
    try std.testing.expect(isFloatInfo(@typeInfo(f64)));
    try std.testing.expect(isFloatInfo(@typeInfo(comptime_float)));
    try std.testing.expect(!isFloatInfo(@typeInfo(i32)));
    try std.testing.expect(!isFloatInfo(@typeInfo(bool)));
}

test "isNumericInfo" {
    try std.testing.expect(isNumericInfo(@typeInfo(i32)));
    try std.testing.expect(isNumericInfo(@typeInfo(f64)));
    try std.testing.expect(!isNumericInfo(@typeInfo(bool)));
    try std.testing.expect(!isNumericInfo(@typeInfo([]const u8)));
}

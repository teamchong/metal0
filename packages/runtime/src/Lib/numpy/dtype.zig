//! NumPy-compatible Data Types
//!
//! Defines the dtype enum for numpy arrays, matching NumPy's type system.

const std = @import("std");

/// NumPy-compatible data type enumeration
pub const DType = enum {
    // Floating point
    float16,
    float32,
    float64,

    // Signed integers
    int8,
    int16,
    int32,
    int64,

    // Unsigned integers
    uint8,
    uint16,
    uint32,
    uint64,

    // Other types
    bool_,
    complex64,
    complex128,

    /// Get the size of this dtype in bytes
    pub fn size(self: DType) usize {
        return switch (self) {
            .float16 => 2,
            .float32 => 4,
            .float64 => 8,
            .int8 => 1,
            .int16 => 2,
            .int32 => 4,
            .int64 => 8,
            .uint8 => 1,
            .uint16 => 2,
            .uint32 => 4,
            .uint64 => 8,
            .bool_ => 1,
            .complex64 => 8,
            .complex128 => 16,
        };
    }

    /// Get the NumPy-style name of this dtype
    pub fn name(self: DType) []const u8 {
        return switch (self) {
            .float16 => "float16",
            .float32 => "float32",
            .float64 => "float64",
            .int8 => "int8",
            .int16 => "int16",
            .int32 => "int32",
            .int64 => "int64",
            .uint8 => "uint8",
            .uint16 => "uint16",
            .uint32 => "uint32",
            .uint64 => "uint64",
            .bool_ => "bool",
            .complex64 => "complex64",
            .complex128 => "complex128",
        };
    }

    /// Get the NumPy-style character code
    pub fn char(self: DType) u8 {
        return switch (self) {
            .float16 => 'e',
            .float32 => 'f',
            .float64 => 'd',
            .int8 => 'b',
            .int16 => 'h',
            .int32 => 'i',
            .int64 => 'l',
            .uint8 => 'B',
            .uint16 => 'H',
            .uint32 => 'I',
            .uint64 => 'L',
            .bool_ => '?',
            .complex64 => 'F',
            .complex128 => 'D',
        };
    }

    /// Check if this dtype is a floating point type
    pub fn isFloat(self: DType) bool {
        return switch (self) {
            .float16, .float32, .float64 => true,
            else => false,
        };
    }

    /// Check if this dtype is an integer type
    pub fn isInteger(self: DType) bool {
        return switch (self) {
            .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64 => true,
            else => false,
        };
    }

    /// Check if this dtype is a signed type
    pub fn isSigned(self: DType) bool {
        return switch (self) {
            .int8, .int16, .int32, .int64, .float16, .float32, .float64, .complex64, .complex128 => true,
            else => false,
        };
    }

    /// Check if this dtype is a complex type
    pub fn isComplex(self: DType) bool {
        return switch (self) {
            .complex64, .complex128 => true,
            else => false,
        };
    }

    /// Get the default dtype (float64, like NumPy)
    pub fn default() DType {
        return .float64;
    }

    /// Parse dtype from string (e.g., "float32", "int64")
    pub fn fromString(s: []const u8) ?DType {
        const map = std.StaticStringMap(DType).initComptime(.{
            .{ "float16", .float16 },
            .{ "float32", .float32 },
            .{ "float64", .float64 },
            .{ "float", .float64 },
            .{ "int8", .int8 },
            .{ "int16", .int16 },
            .{ "int32", .int32 },
            .{ "int64", .int64 },
            .{ "int", .int64 },
            .{ "uint8", .uint8 },
            .{ "uint16", .uint16 },
            .{ "uint32", .uint32 },
            .{ "uint64", .uint64 },
            .{ "bool", .bool_ },
            .{ "complex64", .complex64 },
            .{ "complex128", .complex128 },
            .{ "complex", .complex128 },
        });
        return map.get(s);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "dtype size" {
    try std.testing.expectEqual(@as(usize, 4), DType.float32.size());
    try std.testing.expectEqual(@as(usize, 8), DType.float64.size());
    try std.testing.expectEqual(@as(usize, 8), DType.int64.size());
    try std.testing.expectEqual(@as(usize, 1), DType.bool_.size());
}

test "dtype name" {
    try std.testing.expectEqualStrings("float32", DType.float32.name());
    try std.testing.expectEqualStrings("int64", DType.int64.name());
}

test "dtype fromString" {
    try std.testing.expectEqual(DType.float32, DType.fromString("float32"));
    try std.testing.expectEqual(DType.float64, DType.fromString("float"));
    try std.testing.expectEqual(DType.int64, DType.fromString("int"));
    try std.testing.expectEqual(@as(?DType, null), DType.fromString("unknown"));
}

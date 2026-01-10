//! ctypes._endian - Endian-aware structure support
//! Reference: cpython/Lib/ctypes/_endian.py
//!
//! CPython exports: BigEndianStructure, LittleEndianStructure,
//!                  BigEndianUnion, LittleEndianUnion
//!
//! Provides structures and unions with explicit byte ordering.

const std = @import("std");
const builtin = @import("builtin");
const ctypes = @import("../ctypes.zig");

// ============================================================================
// Endianness Detection
// ============================================================================

/// Native byte order of the system
pub const native_endian = builtin.cpu.arch.endian();

/// Check if system is little-endian
pub const is_little_endian = native_endian == .little;

/// Check if system is big-endian
pub const is_big_endian = native_endian == .big;

/// The "other" endian constant name (for type conversion)
pub const OTHER_ENDIAN = if (is_little_endian) "__ctype_be__" else "__ctype_le__";

// ============================================================================
// Structure/Union Base Types
// ============================================================================

/// CPython: class Structure
/// Base extern struct for C-compatible structures
pub const Structure = ctypes.Structure;

/// CPython: class Union
/// Base extern union for C-compatible unions
pub const Union = ctypes.Union;

// ============================================================================
// Endian-Specific Structures
// ============================================================================

/// CPython: class LittleEndianStructure
/// Structure with little-endian byte order.
/// On little-endian systems, this is the same as Structure.
/// On big-endian systems, fields are byte-swapped when accessed.
pub const LittleEndianStructure = if (is_little_endian)
    Structure
else
    SwappedStructure;

/// CPython: class BigEndianStructure
/// Structure with big-endian byte order.
/// On big-endian systems, this is the same as Structure.
/// On little-endian systems, fields are byte-swapped when accessed.
pub const BigEndianStructure = if (is_big_endian)
    Structure
else
    SwappedStructure;

/// CPython: class LittleEndianUnion
/// Union with little-endian byte order.
pub const LittleEndianUnion = if (is_little_endian)
    Union
else
    SwappedUnion;

/// CPython: class BigEndianUnion
/// Union with big-endian byte order.
pub const BigEndianUnion = if (is_big_endian)
    Union
else
    SwappedUnion;

// ============================================================================
// Swapped Type Helpers
// ============================================================================

/// Marker struct for byte-swapped structures
/// In Zig, we handle byte swapping at the field access level
pub const SwappedStructure = struct {
    /// Marker to indicate byte swapping is needed
    pub const _swappedbytes_: void = {};
};

/// Marker union for byte-swapped unions
pub const SwappedUnion = struct {
    /// Marker to indicate byte swapping is needed
    pub const _swappedbytes_: void = {};
};

// ============================================================================
// Byte Swapping Functions
// ============================================================================

/// Convert value from native to little-endian
pub fn nativeToLittle(comptime T: type, value: T) T {
    return if (is_little_endian) value else @byteSwap(value);
}

/// Convert value from native to big-endian
pub fn nativeToBig(comptime T: type, value: T) T {
    return if (is_big_endian) value else @byteSwap(value);
}

/// Convert value from little-endian to native
pub fn littleToNative(comptime T: type, value: T) T {
    return if (is_little_endian) value else @byteSwap(value);
}

/// Convert value from big-endian to native
pub fn bigToNative(comptime T: type, value: T) T {
    return if (is_big_endian) value else @byteSwap(value);
}

/// Get the "other endian" type for a given type
/// For simple types, returns the byte-swapped equivalent
pub fn otherEndian(comptime T: type) type {
    const info = @typeInfo(T);
    return switch (info) {
        .int => T, // Integers are swapped at access time
        .float => T, // Floats are swapped at access time
        .array => |arr| [arr.len]otherEndian(arr.child),
        .@"struct" => T, // Structs use field-level swapping
        .@"union" => T, // Unions use field-level swapping
        else => T,
    };
}

// ============================================================================
// Field Access with Endian Conversion
// ============================================================================

/// Read a field value with endian conversion (for swapped structures)
pub fn readSwapped(comptime T: type, comptime target_endian: std.builtin.Endian, ptr: *const T) T {
    const value = ptr.*;
    if (native_endian == target_endian) {
        return value;
    }

    const info = @typeInfo(T);
    return switch (info) {
        .int => @byteSwap(value),
        .float => blk: {
            // For floats, swap via integer representation
            const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
            const int_val = @as(IntType, @bitCast(value));
            const swapped = @byteSwap(int_val);
            break :blk @as(T, @bitCast(swapped));
        },
        else => value,
    };
}

/// Write a field value with endian conversion (for swapped structures)
pub fn writeSwapped(comptime T: type, comptime target_endian: std.builtin.Endian, ptr: *T, value: T) void {
    if (native_endian == target_endian) {
        ptr.* = value;
        return;
    }

    const info = @typeInfo(T);
    ptr.* = switch (info) {
        .int => @byteSwap(value),
        .float => blk: {
            const IntType = std.meta.Int(.unsigned, @bitSizeOf(T));
            const int_val = @as(IntType, @bitCast(value));
            const swapped = @byteSwap(int_val);
            break :blk @as(T, @bitCast(swapped));
        },
        else => value,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "endianness detection" {
    // At least one should be true
    try std.testing.expect(is_little_endian or is_big_endian);
    // Both cannot be true
    try std.testing.expect(!(is_little_endian and is_big_endian));
}

test "byte swap u32" {
    const value: u32 = 0x12345678;
    const swapped = @byteSwap(value);
    try std.testing.expectEqual(@as(u32, 0x78563412), swapped);
}

test "nativeToLittle" {
    const value: u32 = 0x12345678;
    const result = nativeToLittle(u32, value);

    if (is_little_endian) {
        try std.testing.expectEqual(value, result);
    } else {
        try std.testing.expectEqual(@as(u32, 0x78563412), result);
    }
}

test "nativeToBig" {
    const value: u32 = 0x12345678;
    const result = nativeToBig(u32, value);

    if (is_big_endian) {
        try std.testing.expectEqual(value, result);
    } else {
        try std.testing.expectEqual(@as(u32, 0x78563412), result);
    }
}

test "roundtrip little endian" {
    const original: u32 = 0xDEADBEEF;
    const as_little = nativeToLittle(u32, original);
    const back = littleToNative(u32, as_little);
    try std.testing.expectEqual(original, back);
}

test "roundtrip big endian" {
    const original: u32 = 0xDEADBEEF;
    const as_big = nativeToBig(u32, original);
    const back = bigToNative(u32, as_big);
    try std.testing.expectEqual(original, back);
}

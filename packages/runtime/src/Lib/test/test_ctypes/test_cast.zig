//! test.test_ctypes.test_cast - Tests for ctypes pointer casting
//! Reference: cpython/Lib/test/test_ctypes/test_cast.py
//!
//! Tests for pointer and type casting operations in ctypes including
//! safe casts, reinterpretation, and pointer arithmetic.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Cast Functions
// ============================================================================

/// Cast a pointer to a different type
pub fn cast(comptime T: type, ptr: anytype) T {
    return @ptrCast(@alignCast(ptr));
}

/// Reinterpret bytes as a different type
pub fn reinterpretBytes(comptime T: type, bytes: []const u8) ?T {
    if (bytes.len < @sizeOf(T)) return null;
    return std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]);
}

/// Cast value to bytes
pub fn asBytes(value: anytype) []const u8 {
    return std.mem.asBytes(&value);
}

/// Cast integer to pointer
pub fn intToPtr(comptime T: type, addr: usize) T {
    return @ptrFromInt(addr);
}

/// Cast pointer to integer
pub fn ptrToInt(ptr: anytype) usize {
    return @intFromPtr(ptr);
}

// ============================================================================
// Safe Cast Wrapper
// ============================================================================

/// Result of a cast operation
pub const CastResult = union(enum) {
    success: *anyopaque,
    null_pointer,
    alignment_error,
    type_error,
};

/// Safely cast a pointer with error handling
pub fn safeCast(comptime T: type, ptr: ?*anyopaque) CastResult {
    if (ptr == null) return .null_pointer;

    const addr = @intFromPtr(ptr);
    const alignment = @alignOf(T);
    if (addr % alignment != 0) return .alignment_error;

    return .{ .success = ptr.? };
}

// ============================================================================
// Type Casting Helpers
// ============================================================================

/// Cast between numeric types with bounds checking
pub fn checkedCast(comptime To: type, comptime From: type, value: From) ?To {
    const to_info = @typeInfo(To);
    const from_info = @typeInfo(From);

    // Handle integer to integer
    if (to_info == .int and from_info == .int) {
        if (value < std.math.minInt(To) or value > std.math.maxInt(To)) {
            return null;
        }
        return @intCast(value);
    }

    // Handle float to int
    if (to_info == .int and from_info == .float) {
        if (value < @as(From, @floatFromInt(std.math.minInt(To))) or
            value > @as(From, @floatFromInt(std.math.maxInt(To))))
        {
            return null;
        }
        return @intFromFloat(value);
    }

    // Handle int to float
    if (to_info == .float and from_info == .int) {
        return @floatFromInt(value);
    }

    return null;
}

/// Truncating cast (wraps on overflow)
pub fn truncatingCast(comptime To: type, value: anytype) To {
    return @truncate(value);
}

// ============================================================================
// Pointer Array Casts
// ============================================================================

/// Cast slice to pointer
pub fn sliceToPtr(comptime T: type, slice: []T) [*]T {
    return slice.ptr;
}

/// Cast pointer with length to slice
pub fn ptrToSlice(comptime T: type, ptr: [*]T, len: usize) []T {
    return ptr[0..len];
}

/// Cast byte slice to typed slice
pub fn bytesToSlice(comptime T: type, bytes: []const u8) ?[]const T {
    if (bytes.len % @sizeOf(T) != 0) return null;
    const count = bytes.len / @sizeOf(T);
    const ptr: [*]const T = @ptrCast(@alignCast(bytes.ptr));
    return ptr[0..count];
}

// ============================================================================
// Test Cases
// ============================================================================

fn testBasicCast() !void {
    var value: i32 = 42;
    const ptr: *i32 = &value;
    const void_ptr: *anyopaque = ptr;
    const back: *i32 = cast(*i32, void_ptr);

    try std.testing.expectEqual(@as(i32, 42), back.*);
}

fn testReinterpretBytes() !void {
    const bytes = [_]u8{ 0x01, 0x00, 0x00, 0x00 }; // 1 in little-endian
    const value = reinterpretBytes(i32, &bytes);

    try std.testing.expect(value != null);
    if (_support.is_linux() or _support.is_macos()) {
        // Little-endian systems
        try std.testing.expectEqual(@as(i32, 1), value.?);
    }
}

fn testReinterpretTooShort() !void {
    const bytes = [_]u8{ 0x01, 0x02 }; // Only 2 bytes
    const value = reinterpretBytes(i32, &bytes); // Needs 4 bytes

    try std.testing.expect(value == null);
}

fn testIntToPtr() !void {
    const addr: usize = 0x1000;
    const ptr = intToPtr(*anyopaque, addr);

    try std.testing.expectEqual(addr, ptrToInt(ptr));
}

fn testPtrToInt() !void {
    var value: i32 = 0;
    const ptr = &value;
    const addr = ptrToInt(ptr);

    try std.testing.expect(addr != 0);
    try std.testing.expectEqual(ptr, intToPtr(*i32, addr));
}

fn testSafeCastNull() !void {
    const result = safeCast(i32, null);
    try std.testing.expect(result == .null_pointer);
}

fn testSafeCastSuccess() !void {
    var value: i32 align(4) = 42;
    const ptr: *anyopaque = @ptrCast(&value);
    const result = safeCast(i32, ptr);

    try std.testing.expect(result == .success);
}

fn testCheckedCastValid() !void {
    try std.testing.expectEqual(@as(?i8, 100), checkedCast(i8, i32, 100));
    try std.testing.expectEqual(@as(?u16, 1000), checkedCast(u16, i32, 1000));
}

fn testCheckedCastOverflow() !void {
    try std.testing.expectEqual(@as(?i8, null), checkedCast(i8, i32, 200)); // > 127
    try std.testing.expectEqual(@as(?u8, null), checkedCast(u8, i32, -1)); // < 0
}

fn testTruncatingCast() !void {
    const big: u32 = 0x12345678;
    const low_byte: u8 = truncatingCast(u8, big);
    try std.testing.expectEqual(@as(u8, 0x78), low_byte);

    const low_word: u16 = truncatingCast(u16, big);
    try std.testing.expectEqual(@as(u16, 0x5678), low_word);
}

fn testSliceToPtr() !void {
    var arr = [_]i32{ 1, 2, 3, 4, 5 };
    const ptr = sliceToPtr(i32, &arr);

    try std.testing.expectEqual(@as(i32, 1), ptr[0]);
    try std.testing.expectEqual(@as(i32, 3), ptr[2]);
}

fn testPtrToSlice() !void {
    var arr = [_]i32{ 10, 20, 30 };
    const ptr: [*]i32 = &arr;
    const slice = ptrToSlice(i32, ptr, 3);

    try std.testing.expectEqual(@as(usize, 3), slice.len);
    try std.testing.expectEqual(@as(i32, 20), slice[1]);
}

fn testBytesToSlice() !void {
    const bytes = [_]u8{ 0x01, 0x00, 0x02, 0x00 }; // Two u16 values
    const result = bytesToSlice(u16, &bytes);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?.len);
}

fn testBytesToSliceMisaligned() !void {
    const bytes = [_]u8{ 0x01, 0x02, 0x03 }; // 3 bytes, not divisible by 4
    const result = bytesToSlice(u32, &bytes);

    try std.testing.expect(result == null);
}

fn testFloatToIntCast() !void {
    try std.testing.expectEqual(@as(?i32, 42), checkedCast(i32, f64, 42.0));
    try std.testing.expectEqual(@as(?i32, 42), checkedCast(i32, f64, 42.9)); // Truncates
}

fn testIntToFloatCast() !void {
    const result = checkedCast(f64, i32, 42);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), result.?, 0.001);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "basic_cast" {
    try testBasicCast();
}

test "reinterpret_bytes" {
    try testReinterpretBytes();
}

test "reinterpret_too_short" {
    try testReinterpretTooShort();
}

test "int_to_ptr" {
    try testIntToPtr();
}

test "ptr_to_int" {
    try testPtrToInt();
}

test "safe_cast_null" {
    try testSafeCastNull();
}

test "safe_cast_success" {
    try testSafeCastSuccess();
}

test "checked_cast_valid" {
    try testCheckedCastValid();
}

test "checked_cast_overflow" {
    try testCheckedCastOverflow();
}

test "truncating_cast" {
    try testTruncatingCast();
}

test "slice_to_ptr" {
    try testSliceToPtr();
}

test "ptr_to_slice" {
    try testPtrToSlice();
}

test "bytes_to_slice" {
    try testBytesToSlice();
}

test "bytes_to_slice_misaligned" {
    try testBytesToSliceMisaligned();
}

test "float_to_int_cast" {
    try testFloatToIntCast();
}

test "int_to_float_cast" {
    try testIntToFloatCast();
}

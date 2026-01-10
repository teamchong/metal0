//! test.test_ctypes.test_memfunctions - Tests for memory functions
//! Reference: cpython/Lib/test/test_ctypes/test_memfunctions.py
//!
//! Tests for ctypes memory manipulation functions including
//! memmove, memset, string_at, and wstring_at.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Memory Functions
// ============================================================================

/// Move memory (handles overlapping regions)
pub fn memmove(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    const dest_slice = dest[0..n];
    const src_slice = src[0..n];

    if (@intFromPtr(dest) < @intFromPtr(src)) {
        @memcpy(dest_slice, src_slice);
    } else {
        // Copy backwards for overlapping regions where dest > src
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            dest[i] = src[i];
        }
    }
    return dest;
}

/// Set memory to a value
pub fn memset(dest: [*]u8, c: u8, n: usize) [*]u8 {
    @memset(dest[0..n], c);
    return dest;
}

/// Get string from memory address
pub fn string_at(addr: [*]const u8, size: ?usize) []const u8 {
    if (size) |s| {
        return addr[0..s];
    } else {
        // Find null terminator
        var len: usize = 0;
        while (addr[len] != 0) : (len += 1) {}
        return addr[0..len];
    }
}

/// Get wide string from memory address
pub fn wstring_at(addr: [*]const u16, size: ?usize) []const u16 {
    if (size) |s| {
        return addr[0..s];
    } else {
        // Find null terminator
        var len: usize = 0;
        while (addr[len] != 0) : (len += 1) {}
        return addr[0..len];
    }
}

// ============================================================================
// Memory Allocation Wrappers
// ============================================================================

/// Create a string buffer
pub fn create_string_buffer(init: ?[]const u8, size: usize, allocator: std.mem.Allocator) ![]u8 {
    const buf = try allocator.alloc(u8, size);
    @memset(buf, 0);

    if (init) |s| {
        const len = @min(s.len, size - 1);
        @memcpy(buf[0..len], s[0..len]);
    }

    return buf;
}

/// Create a unicode buffer
pub fn create_unicode_buffer(init: ?[]const u16, size: usize, allocator: std.mem.Allocator) ![]u16 {
    const buf = try allocator.alloc(u16, size);
    @memset(buf, 0);

    if (init) |s| {
        const len = @min(s.len, size - 1);
        @memcpy(buf[0..len], s[0..len]);
    }

    return buf;
}

// ============================================================================
// Pointer Operations
// ============================================================================

/// Cast pointer to address
pub fn addressof(ptr: anytype) usize {
    return @intFromPtr(ptr);
}

/// Cast address to pointer
pub fn cast_ptr(comptime T: type, addr: usize) T {
    return @ptrFromInt(addr);
}

/// Get size of data at pointer
pub fn sizeof(ptr: anytype) usize {
    const PtrType = @TypeOf(ptr);
    const info = @typeInfo(PtrType);
    if (info == .pointer) {
        return @sizeOf(info.pointer.child);
    }
    return 0;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testMemmove() !void {
    var buf: [20]u8 = undefined;
    @memcpy(buf[0..5], "Hello");

    // Non-overlapping copy
    _ = memmove(buf[10..].ptr, buf[0..].ptr, 5);
    try std.testing.expectEqualStrings("Hello", buf[10..15]);

    // Overlapping copy (forward)
    _ = memmove(buf[2..].ptr, buf[0..].ptr, 5);
    try std.testing.expectEqualStrings("Hello", buf[2..7]);
}

fn testMemmoveOverlap() !void {
    var buf: [10]u8 = undefined;
    @memcpy(buf[0..5], "ABCDE");

    // Overlapping copy (backward, dest > src)
    _ = memmove(buf[2..].ptr, buf[0..].ptr, 5);
    try std.testing.expectEqualStrings("ABCDE", buf[2..7]);
}

fn testMemset() !void {
    var buf: [10]u8 = undefined;
    _ = memset(&buf, 'X', 10);

    for (buf) |c| {
        try std.testing.expectEqual(@as(u8, 'X'), c);
    }
}

fn testMemsetPartial() !void {
    var buf: [10]u8 = undefined;
    @memset(&buf, 0);
    _ = memset(buf[2..].ptr, 'A', 5);

    try std.testing.expectEqual(@as(u8, 0), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[1]);
    try std.testing.expectEqual(@as(u8, 'A'), buf[2]);
    try std.testing.expectEqual(@as(u8, 'A'), buf[6]);
    try std.testing.expectEqual(@as(u8, 0), buf[7]);
}

fn testStringAt() !void {
    const data = "Hello, World!\x00Extra";

    // With explicit size
    const s1 = string_at(data.ptr, 5);
    try std.testing.expectEqualStrings("Hello", s1);

    // Without size (null-terminated)
    const s2 = string_at(data.ptr, null);
    try std.testing.expectEqualStrings("Hello, World!", s2);
}

fn testWstringAt() !void {
    const data = [_]u16{ 'H', 'i', 0, 'X' };

    // With explicit size
    const s1 = wstring_at(&data, 2);
    try std.testing.expectEqual(@as(usize, 2), s1.len);

    // Without size (null-terminated)
    const s2 = wstring_at(&data, null);
    try std.testing.expectEqual(@as(usize, 2), s2.len);
}

fn testCreateStringBuffer() !void {
    const allocator = std.testing.allocator;

    const buf = try create_string_buffer("Test", 10, allocator);
    defer allocator.free(buf);

    try std.testing.expectEqualStrings("Test", buf[0..4]);
    try std.testing.expectEqual(@as(u8, 0), buf[4]);
    try std.testing.expectEqual(@as(usize, 10), buf.len);
}

fn testCreateStringBufferEmpty() !void {
    const allocator = std.testing.allocator;

    const buf = try create_string_buffer(null, 20, allocator);
    defer allocator.free(buf);

    for (buf) |c| {
        try std.testing.expectEqual(@as(u8, 0), c);
    }
}

fn testAddressof() !void {
    var value: i32 = 42;
    const addr = addressof(&value);

    try std.testing.expect(addr != 0);
    try std.testing.expectEqual(&value, cast_ptr(*i32, addr));
}

fn testSizeof() !void {
    var i: i32 = 0;
    try std.testing.expectEqual(@as(usize, 4), sizeof(&i));

    var d: f64 = 0;
    try std.testing.expectEqual(@as(usize, 8), sizeof(&d));
}

fn testCastPtr() !void {
    var value: i32 = 12345;
    const addr = @intFromPtr(&value);
    const ptr = cast_ptr(*i32, addr);

    try std.testing.expectEqual(@as(i32, 12345), ptr.*);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "memmove" {
    try testMemmove();
}

test "memmove_overlap" {
    try testMemmoveOverlap();
}

test "memset" {
    try testMemset();
}

test "memset_partial" {
    try testMemsetPartial();
}

test "string_at" {
    try testStringAt();
}

test "wstring_at" {
    try testWstringAt();
}

test "create_string_buffer" {
    try testCreateStringBuffer();
}

test "create_string_buffer_empty" {
    try testCreateStringBufferEmpty();
}

test "addressof" {
    try testAddressof();
}

test "sizeof" {
    try testSizeof();
}

test "cast_ptr" {
    try testCastPtr();
}

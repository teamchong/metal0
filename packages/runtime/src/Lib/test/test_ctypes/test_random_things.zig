//! test.test_ctypes.test_random_things - Miscellaneous tests
//! Reference: cpython/Lib/test/test_ctypes/test_random_things.py
//!
//! Tests for miscellaneous ctypes functionality.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Miscellaneous Types
// ============================================================================

/// A type that can be compared
pub fn Comparable(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.value == other.value;
        }

        pub fn lessThan(self: Self, other: Self) bool {
            return self.value < other.value;
        }

        pub fn hash(self: Self) u64 {
            return @intCast(@as(u32, @truncate(@as(u64, @bitCast(self.value)))));
        }
    };
}

/// A type that can be converted to/from bytes
pub fn ByteConvertible(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn toBytes(self: *const Self) []const u8 {
            return std.mem.asBytes(&self.value);
        }

        pub fn fromBytes(bytes: []const u8) !Self {
            if (bytes.len < @sizeOf(T)) return error.InsufficientBytes;
            return .{ .value = std.mem.bytesToValue(T, bytes[0..@sizeOf(T)]) };
        }
    };
}

// ============================================================================
// Edge Cases
// ============================================================================

/// Empty structure
pub const EmptyStruct = struct {
    pub fn sizeof() usize {
        return 0;
    }
};

/// Single-byte structure
pub const SingleByte = struct {
    value: u8 = 0,

    pub fn init(v: u8) SingleByte {
        return .{ .value = v };
    }
};

/// Maximum-aligned structure
pub const MaxAligned = struct {
    value: u64 align(16) = 0,

    pub fn init(v: u64) MaxAligned {
        return .{ .value = v };
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Get the alignment of a type
pub fn alignmentOf(comptime T: type) usize {
    return @alignOf(T);
}

/// Get the size of a type
pub fn sizeOf(comptime T: type) usize {
    return @sizeOf(T);
}

/// Check if two types have the same size
pub fn sameSizeAs(comptime A: type, comptime B: type) bool {
    return @sizeOf(A) == @sizeOf(B);
}

/// Check if a type is a pointer
pub fn isPointer(comptime T: type) bool {
    return @typeInfo(T) == .pointer;
}

/// Check if a type is numeric
pub fn isNumeric(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .int or info == .float;
}

// ============================================================================
// String Utilities
// ============================================================================

/// Create a null-terminated string
pub fn createCString(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const result = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(result, s);
    return result;
}

/// Get length of null-terminated string
pub fn cstrlen(s: [*:0]const u8) usize {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    return len;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testComparable() !void {
    const a = Comparable(i32).init(10);
    const b = Comparable(i32).init(10);
    const c = Comparable(i32).init(20);

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
    try std.testing.expect(a.lessThan(c));
}

fn testByteConvertible() !void {
    const original = ByteConvertible(i32).init(12345);
    const bytes = original.toBytes();

    const restored = try ByteConvertible(i32).fromBytes(bytes);
    try std.testing.expectEqual(@as(i32, 12345), restored.value);
}

fn testEmptyStruct() !void {
    try std.testing.expectEqual(@as(usize, 0), EmptyStruct.sizeof());
    // Note: Zig may not allow zero-sized types in some contexts
}

fn testSingleByte() !void {
    const sb = SingleByte.init(0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), sb.value);
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(SingleByte));
}

fn testMaxAligned() !void {
    const ma = MaxAligned.init(12345);
    try std.testing.expectEqual(@as(u64, 12345), ma.value);
    try std.testing.expect(@alignOf(MaxAligned) >= 16);
}

fn testAlignmentOf() !void {
    try std.testing.expectEqual(@as(usize, 1), alignmentOf(u8));
    try std.testing.expectEqual(@as(usize, 4), alignmentOf(i32));
    try std.testing.expectEqual(@as(usize, 8), alignmentOf(f64));
}

fn testSizeOf() !void {
    try std.testing.expectEqual(@as(usize, 1), sizeOf(u8));
    try std.testing.expectEqual(@as(usize, 4), sizeOf(i32));
    try std.testing.expectEqual(@as(usize, 8), sizeOf(i64));
}

fn testSameSizeAs() !void {
    try std.testing.expect(sameSizeAs(i32, u32));
    try std.testing.expect(sameSizeAs(i32, f32));
    try std.testing.expect(!sameSizeAs(i32, i64));
}

fn testIsPointer() !void {
    try std.testing.expect(isPointer(*i32));
    try std.testing.expect(isPointer([*]u8));
    try std.testing.expect(!isPointer(i32));
}

fn testIsNumeric() !void {
    try std.testing.expect(isNumeric(i32));
    try std.testing.expect(isNumeric(f64));
    try std.testing.expect(!isNumeric(bool));
}

fn testCreateCString() !void {
    const allocator = std.testing.allocator;
    const s = try createCString(allocator, "Hello");
    defer allocator.free(s);

    try std.testing.expectEqualStrings("Hello", s);
    try std.testing.expectEqual(@as(u8, 0), s[5]);
}

fn testCstrlen() !void {
    try std.testing.expectEqual(@as(usize, 0), cstrlen(""));
    try std.testing.expectEqual(@as(usize, 5), cstrlen("Hello"));
}

fn testComparableHash() !void {
    const a = Comparable(i32).init(42);
    const b = Comparable(i32).init(42);
    const c = Comparable(i32).init(43);

    try std.testing.expectEqual(a.hash(), b.hash());
    try std.testing.expect(a.hash() != c.hash());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "comparable" {
    try testComparable();
}

test "byte_convertible" {
    try testByteConvertible();
}

test "empty_struct" {
    try testEmptyStruct();
}

test "single_byte" {
    try testSingleByte();
}

test "max_aligned" {
    try testMaxAligned();
}

test "alignment_of" {
    try testAlignmentOf();
}

test "size_of" {
    try testSizeOf();
}

test "same_size_as" {
    try testSameSizeAs();
}

test "is_pointer" {
    try testIsPointer();
}

test "is_numeric" {
    try testIsNumeric();
}

test "create_c_string" {
    try testCreateCString();
}

test "cstrlen" {
    try testCstrlen();
}

test "comparable_hash" {
    try testComparableHash();
}

//! Python 'bisect' module - Array bisection algorithm
//!
//! Provides support for maintaining a list in sorted order without having
//! to sort the list after each insertion. Uses binary search.
//!
//! Mirrors: CPython Lib/bisect.py

const std = @import("std");

/// Locate the insertion point for x in a to maintain sorted order.
/// If x is already present, the insertion point will be before (to the left of)
/// any existing entries.
pub fn bisect_left(comptime T: type, a: []const T, x: T) usize {
    return bisect_left_range(T, a, x, 0, a.len);
}

/// bisect_left with explicit lo and hi bounds
pub fn bisect_left_range(comptime T: type, a: []const T, x: T, lo: usize, hi: usize) usize {
    var low = lo;
    var high = hi;

    while (low < high) {
        const mid = low + (high - low) / 2;
        if (a[mid] < x) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

/// Locate the insertion point for x in a to maintain sorted order.
/// If x is already present, the insertion point will be after (to the right of)
/// any existing entries.
pub fn bisect_right(comptime T: type, a: []const T, x: T) usize {
    return bisect_right_range(T, a, x, 0, a.len);
}

/// bisect_right with explicit lo and hi bounds
pub fn bisect_right_range(comptime T: type, a: []const T, x: T, lo: usize, hi: usize) usize {
    var low = lo;
    var high = hi;

    while (low < high) {
        const mid = low + (high - low) / 2;
        if (x < a[mid]) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    return low;
}

/// Alias for bisect_right (default bisect behavior)
pub const bisect = bisect_right;

/// Insert x in list a, and keep it sorted assuming a is sorted.
/// If x is already in a, insert it to the left of the leftmost x.
pub fn insort_left(comptime T: type, a: *std.ArrayList(T), x: T) !void {
    const pos = bisect_left(T, a.items, x);
    try a.insert(pos, x);
}

/// insort_left with explicit lo and hi bounds
pub fn insort_left_range(comptime T: type, a: *std.ArrayList(T), x: T, lo: usize, hi: usize) !void {
    const pos = bisect_left_range(T, a.items, x, lo, hi);
    try a.insert(pos, x);
}

/// Insert x in list a, and keep it sorted assuming a is sorted.
/// If x is already in a, insert it to the right of the rightmost x.
pub fn insort_right(comptime T: type, a: *std.ArrayList(T), x: T) !void {
    const pos = bisect_right(T, a.items, x);
    try a.insert(pos, x);
}

/// insort_right with explicit lo and hi bounds
pub fn insort_right_range(comptime T: type, a: *std.ArrayList(T), x: T, lo: usize, hi: usize) !void {
    const pos = bisect_right_range(T, a.items, x, lo, hi);
    try a.insert(pos, x);
}

/// Alias for insort_right (default insort behavior)
pub const insort = insort_right;

// ============================================================================
// Key-based versions (using a key function)
// ============================================================================

/// bisect_left with a key function
pub fn bisect_left_by_key(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    comptime key: fn (T) K,
) usize {
    return bisect_left_by_key_range(T, K, a, x, 0, a.len, key);
}

/// bisect_left_by_key with explicit lo and hi bounds
pub fn bisect_left_by_key_range(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    lo: usize,
    hi: usize,
    comptime key: fn (T) K,
) usize {
    var low = lo;
    var high = hi;

    while (low < high) {
        const mid = low + (high - low) / 2;
        if (key(a[mid]) < x) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

/// bisect_right with a key function
pub fn bisect_right_by_key(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    comptime key: fn (T) K,
) usize {
    return bisect_right_by_key_range(T, K, a, x, 0, a.len, key);
}

/// bisect_right_by_key with explicit lo and hi bounds
pub fn bisect_right_by_key_range(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    lo: usize,
    hi: usize,
    comptime key: fn (T) K,
) usize {
    var low = lo;
    var high = hi;

    while (low < high) {
        const mid = low + (high - low) / 2;
        if (x < key(a[mid])) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    return low;
}

// ============================================================================
// Utility functions using bisect
// ============================================================================

/// Find index of first element >= x
pub fn find_ge(comptime T: type, a: []const T, x: T) ?usize {
    const i = bisect_left(T, a, x);
    if (i < a.len) return i;
    return null;
}

/// Find index of first element > x
pub fn find_gt(comptime T: type, a: []const T, x: T) ?usize {
    const i = bisect_right(T, a, x);
    if (i < a.len) return i;
    return null;
}

/// Find index of last element <= x
pub fn find_le(comptime T: type, a: []const T, x: T) ?usize {
    const i = bisect_right(T, a, x);
    if (i > 0) return i - 1;
    return null;
}

/// Find index of last element < x
pub fn find_lt(comptime T: type, a: []const T, x: T) ?usize {
    const i = bisect_left(T, a, x);
    if (i > 0) return i - 1;
    return null;
}

/// Binary search: find index of x if present
pub fn index(comptime T: type, a: []const T, x: T) ?usize {
    const i = bisect_left(T, a, x);
    if (i < a.len and a[i] == x) return i;
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "bisect_left" {
    const arr = [_]i32{ 1, 2, 4, 4, 5, 6 };

    try std.testing.expectEqual(@as(usize, 0), bisect_left(i32, &arr, 0));
    try std.testing.expectEqual(@as(usize, 0), bisect_left(i32, &arr, 1));
    try std.testing.expectEqual(@as(usize, 1), bisect_left(i32, &arr, 2));
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 3));
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 4)); // Left of first 4
    try std.testing.expectEqual(@as(usize, 6), bisect_left(i32, &arr, 7));
}

test "bisect_right" {
    const arr = [_]i32{ 1, 2, 4, 4, 5, 6 };

    try std.testing.expectEqual(@as(usize, 0), bisect_right(i32, &arr, 0));
    try std.testing.expectEqual(@as(usize, 1), bisect_right(i32, &arr, 1));
    try std.testing.expectEqual(@as(usize, 2), bisect_right(i32, &arr, 2));
    try std.testing.expectEqual(@as(usize, 2), bisect_right(i32, &arr, 3));
    try std.testing.expectEqual(@as(usize, 4), bisect_right(i32, &arr, 4)); // Right of last 4
    try std.testing.expectEqual(@as(usize, 6), bisect_right(i32, &arr, 7));
}

test "insort_left" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try insort_left(i32, &list, 3);
    try insort_left(i32, &list, 1);
    try insort_left(i32, &list, 2);
    try insort_left(i32, &list, 2);

    const expected = [_]i32{ 1, 2, 2, 3 };
    try std.testing.expectEqualSlices(i32, &expected, list.items);
}

test "insort_right" {
    const allocator = std.testing.allocator;
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    try insort_right(i32, &list, 3);
    try insort_right(i32, &list, 1);
    try insort_right(i32, &list, 2);

    const expected = [_]i32{ 1, 2, 3 };
    try std.testing.expectEqualSlices(i32, &expected, list.items);
}

test "find functions" {
    const arr = [_]i32{ 1, 2, 4, 5, 6 };

    try std.testing.expectEqual(@as(?usize, 2), find_ge(i32, &arr, 3)); // 4 >= 3
    try std.testing.expectEqual(@as(?usize, 2), find_ge(i32, &arr, 4)); // 4 >= 4
    try std.testing.expectEqual(@as(?usize, 3), find_gt(i32, &arr, 4)); // 5 > 4
    try std.testing.expectEqual(@as(?usize, 1), find_le(i32, &arr, 3)); // 2 <= 3
    try std.testing.expectEqual(@as(?usize, 2), find_le(i32, &arr, 4)); // 4 <= 4
    try std.testing.expectEqual(@as(?usize, 1), find_lt(i32, &arr, 4)); // 2 < 4
}

test "index binary search" {
    const arr = [_]i32{ 1, 2, 4, 5, 6 };

    try std.testing.expectEqual(@as(?usize, 0), index(i32, &arr, 1));
    try std.testing.expectEqual(@as(?usize, 2), index(i32, &arr, 4));
    try std.testing.expectEqual(@as(?usize, null), index(i32, &arr, 3));
}

test "bisect empty array" {
    const arr = [_]i32{};

    try std.testing.expectEqual(@as(usize, 0), bisect_left(i32, &arr, 1));
    try std.testing.expectEqual(@as(usize, 0), bisect_right(i32, &arr, 1));
}

test "bisect with range" {
    const arr = [_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };

    // Search only in range [2, 6) (indices 2-5 containing 3,4,5,6)
    try std.testing.expectEqual(@as(usize, 2), bisect_left_range(i32, &arr, 3, 2, 6));
    try std.testing.expectEqual(@as(usize, 3), bisect_left_range(i32, &arr, 4, 2, 6));
    try std.testing.expectEqual(@as(usize, 6), bisect_left_range(i32, &arr, 7, 2, 6));
}

fn getFirst(pair: [2]i32) i32 {
    return pair[0];
}

test "bisect with key function" {
    const arr = [_][2]i32{
        .{ 1, 10 },
        .{ 3, 30 },
        .{ 5, 50 },
    };

    // Search by first element
    try std.testing.expectEqual(@as(usize, 1), bisect_left_by_key([2]i32, i32, &arr, 2, getFirst));
    try std.testing.expectEqual(@as(usize, 1), bisect_left_by_key([2]i32, i32, &arr, 3, getFirst));
    try std.testing.expectEqual(@as(usize, 2), bisect_right_by_key([2]i32, i32, &arr, 3, getFirst));
}

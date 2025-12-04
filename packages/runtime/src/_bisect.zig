/// _bisect - C accelerator module for bisect
/// Array bisection algorithms for maintaining sorted lists
const std = @import("std");

/// Locate the insertion point for x in a to maintain sorted order.
/// If x is already present, the insertion point will be to the left.
/// Return value i is such that all e in a[:i] have e < x, and all e in a[i:] have e >= x.
pub fn bisect_left(comptime T: type, a: []const T, x: T, lo: usize, hi: ?usize) usize {
    var low = lo;
    var high = hi orelse a.len;

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
/// If x is already present, the insertion point will be to the right.
/// Return value i is such that all e in a[:i] have e <= x, and all e in a[i:] have e > x.
pub fn bisect_right(comptime T: type, a: []const T, x: T, lo: usize, hi: ?usize) usize {
    var low = lo;
    var high = hi orelse a.len;

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

/// Alias for bisect_right
pub const bisect = bisect_right;

/// Insert x in a in sorted order.
/// This is equivalent to a.insert(bisect_left(a, x, lo, hi), x) assuming that
/// a is already sorted.
pub fn insort_left(comptime T: type, a: *std.ArrayList(T), x: T, lo: usize, hi: ?usize, allocator: std.mem.Allocator) !void {
    const idx = bisect_left(T, a.items, x, lo, hi);
    try a.insert(allocator, idx, x);
}

/// Insert x in a in sorted order.
/// This is equivalent to a.insert(bisect_right(a, x, lo, hi), x) assuming that
/// a is already sorted.
pub fn insort_right(comptime T: type, a: *std.ArrayList(T), x: T, lo: usize, hi: ?usize, allocator: std.mem.Allocator) !void {
    const idx = bisect_right(T, a.items, x, lo, hi);
    try a.insert(allocator, idx, x);
}

/// Alias for insort_right
pub const insort = insort_right;

/// bisect_left with key function
pub fn bisect_left_key(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    lo: usize,
    hi: ?usize,
    key: *const fn (T) K,
) usize {
    var low = lo;
    var high = hi orelse a.len;

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

/// bisect_right with key function
pub fn bisect_right_key(
    comptime T: type,
    comptime K: type,
    a: []const T,
    x: K,
    lo: usize,
    hi: ?usize,
    key: *const fn (T) K,
) usize {
    var low = lo;
    var high = hi orelse a.len;

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
// Tests
// ============================================================================

test "bisect_left" {
    const arr = [_]i32{ 1, 3, 5, 7, 9 };

    // Element exists
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 5, 0, null));

    // Element doesn't exist
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 4, 0, null));

    // Before first
    try std.testing.expectEqual(@as(usize, 0), bisect_left(i32, &arr, 0, 0, null));

    // After last
    try std.testing.expectEqual(@as(usize, 5), bisect_left(i32, &arr, 10, 0, null));
}

test "bisect_right" {
    const arr = [_]i32{ 1, 3, 5, 5, 7, 9 };

    // Element exists (goes to right of duplicates)
    try std.testing.expectEqual(@as(usize, 4), bisect_right(i32, &arr, 5, 0, null));

    // Element doesn't exist
    try std.testing.expectEqual(@as(usize, 2), bisect_right(i32, &arr, 4, 0, null));

    // Before first
    try std.testing.expectEqual(@as(usize, 0), bisect_right(i32, &arr, 0, 0, null));

    // After last
    try std.testing.expectEqual(@as(usize, 6), bisect_right(i32, &arr, 10, 0, null));
}

test "insort" {
    const allocator = std.testing.allocator;
    var arr = std.ArrayList(i32).init(allocator);
    defer arr.deinit(allocator);

    try insort(i32, &arr, 5, 0, null, allocator);
    try insort(i32, &arr, 3, 0, null, allocator);
    try insort(i32, &arr, 7, 0, null, allocator);
    try insort(i32, &arr, 1, 0, null, allocator);
    try insort(i32, &arr, 9, 0, null, allocator);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 1, 3, 5, 7, 9 }, arr.items);
}

test "bisect with bounded range" {
    const arr = [_]i32{ 1, 3, 5, 7, 9 };

    // Only search in middle portion
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 4, 1, 4));
    try std.testing.expectEqual(@as(usize, 2), bisect_left(i32, &arr, 5, 1, 4));
}

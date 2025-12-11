/// Utility functions for itertools - collect, product runtime function
const std = @import("std");

// ============================================================================
// Convenience functions to collect iterator results
// ============================================================================

/// Collect all elements from an iterator into a slice
pub fn collect(comptime T: type, comptime Iter: type, iter: *Iter, allocator: std.mem.Allocator) ![]T {
    var result: std.ArrayList(T) = .{};
    while (iter.next()) |item| {
        try result.append(allocator, item);
    }
    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Runtime-callable product function (for `from itertools import product`)
// ============================================================================

const itertools_ops = @import("../../runtime/itertools_ops.zig");

/// product(iterable, repeat_n) - Cartesian product of input iterable with itself repeat_n times
/// product(range(3), 2) -> [[0,0], [0,1], [0,2], ...]
/// Handles slices of i64 (most common case for range())
pub fn product(iterable: []const i64, repeat_count: i64) ![][]i64 {
    const n: usize = @intCast(repeat_count);
    const allocator = std.heap.c_allocator;
    return itertools_ops.productRepeat(i64, allocator, iterable, n);
}

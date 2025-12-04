/// _heapq - C accelerator module for heapq
/// Heap queue algorithm (a.k.a. priority queue)
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Push item onto heap, maintaining the heap invariant
pub fn heappush(comptime T: type, heap: *std.ArrayList(T), item: T, allocator: Allocator) !void {
    try heap.append(allocator, item);
    siftdown(T, heap.items, 0, heap.items.len - 1);
}

/// Pop the smallest item off the heap, maintaining the heap invariant
pub fn heappop(comptime T: type, heap: *std.ArrayList(T)) !T {
    if (heap.items.len == 0) return error.IndexError;

    const last = heap.pop() orelse return error.IndexError;
    if (heap.items.len > 0) {
        const result = heap.items[0];
        heap.items[0] = last;
        siftup(T, heap.items, 0);
        return result;
    }
    return last;
}

/// Pop and return the current smallest value, and add the new item
/// This is more efficient than heappop() followed by heappush()
pub fn heapreplace(comptime T: type, heap: *std.ArrayList(T), item: T) !T {
    if (heap.items.len == 0) return error.IndexError;

    const result = heap.items[0];
    heap.items[0] = item;
    siftup(T, heap.items, 0);
    return result;
}

/// Push item on the heap, then pop and return the smallest item
/// More efficient than heappush() followed by heappop()
pub fn heappushpop(comptime T: type, heap: *std.ArrayList(T), item: T, allocator: Allocator) !T {
    if (heap.items.len > 0 and heap.items[0] < item) {
        const result = heap.items[0];
        heap.items[0] = item;
        siftup(T, heap.items, 0);
        return result;
    }
    _ = allocator;
    return item;
}

/// Transform list into a heap, in-place, in O(len(x)) time
pub fn heapify(comptime T: type, x: []T) void {
    const n = x.len;
    // Transform bottom-up. Largest index with a child is (n-1)/2
    if (n > 1) {
        var i: usize = n / 2;
        while (i > 0) {
            i -= 1;
            siftup(T, x, i);
        }
    }
}

/// Find the n largest elements in a dataset
pub fn nlargest(comptime T: type, n: usize, iterable: []const T, allocator: Allocator) ![]T {
    if (n == 0) return &[_]T{};
    if (n >= iterable.len) {
        const result = try allocator.alloc(T, iterable.len);
        @memcpy(result, iterable);
        // Sort descending
        std.mem.sort(T, result, {}, struct {
            fn cmp(_: void, a: T, b: T) bool {
                return a > b;
            }
        }.cmp);
        return result;
    }

    // Use a min-heap of size n
    var heap: std.ArrayList(T) = .empty;
    defer heap.deinit(allocator);

    // Add first n items
    for (iterable[0..n]) |item| {
        try heap.append(allocator, item);
    }
    heapify(T, heap.items);

    // For remaining items, if larger than smallest in heap, replace
    for (iterable[n..]) |item| {
        if (item > heap.items[0]) {
            _ = try heapreplace(T, &heap, item);
        }
    }

    // Extract all items - heappop gives smallest first (ascending)
    // We fill backwards so result has descending order
    var result = try allocator.alloc(T, heap.items.len);
    var i: usize = heap.items.len;
    while (heap.items.len > 0) {
        i -= 1;
        result[i] = try heappop(T, &heap);
    }
    // result is now in descending order (largest first)
    return result;
}

/// Find the n smallest elements in a dataset
pub fn nsmallest(comptime T: type, n: usize, iterable: []const T, allocator: Allocator) ![]T {
    if (n == 0) return &[_]T{};
    if (n >= iterable.len) {
        const result = try allocator.alloc(T, iterable.len);
        @memcpy(result, iterable);
        std.mem.sort(T, result, {}, std.sort.asc(T));
        return result;
    }

    // Use a max-heap of size n (negate values for min behavior)
    var heap: std.ArrayList(T) = .empty;
    defer heap.deinit(allocator);

    // Simple approach: heapify all, pop n times
    for (iterable) |item| {
        try heap.append(allocator, item);
    }
    heapify(T, heap.items);

    var result = try allocator.alloc(T, n);
    for (0..n) |i| {
        result[i] = try heappop(T, &heap);
    }
    return result;
}

// Internal sift functions

/// Sift down - move item at pos down to leaf level, then bubble up
fn siftup(comptime T: type, heap: []T, pos: usize) void {
    const end_pos = heap.len;
    const start_pos = pos;
    const new_item = heap[pos];
    var child_pos = 2 * pos + 1; // leftmost child

    var current_pos = pos;
    while (child_pos < end_pos) {
        // Set child_pos to index of smaller child
        const right_pos = child_pos + 1;
        if (right_pos < end_pos and heap[right_pos] < heap[child_pos]) {
            child_pos = right_pos;
        }
        // Move the smaller child up
        heap[current_pos] = heap[child_pos];
        current_pos = child_pos;
        child_pos = 2 * current_pos + 1;
    }

    // The leaf at current_pos is empty now. Put new_item there and bubble up
    heap[current_pos] = new_item;
    siftdown(T, heap, start_pos, current_pos);
}

/// Sift down - bubble item at pos up to its proper position
fn siftdown(comptime T: type, heap: []T, start_pos: usize, pos: usize) void {
    const new_item = heap[pos];
    var current_pos = pos;

    while (current_pos > start_pos) {
        const parent_pos = (current_pos - 1) >> 1;
        const parent = heap[parent_pos];
        if (new_item < parent) {
            heap[current_pos] = parent;
            current_pos = parent_pos;
        } else {
            break;
        }
    }
    heap[current_pos] = new_item;
}

// ============================================================================
// Merge function for sorted iterables
// ============================================================================

/// Merge multiple sorted inputs into a single sorted output
pub fn merge(comptime T: type, iterables: []const []const T, allocator: Allocator) ![]T {
    // Calculate total length
    var total_len: usize = 0;
    for (iterables) |it| {
        total_len += it.len;
    }

    if (total_len == 0) return &[_]T{};

    var result = try allocator.alloc(T, total_len);
    var indices = try allocator.alloc(usize, iterables.len);
    defer allocator.free(indices);
    @memset(indices, 0);

    var out_idx: usize = 0;
    while (out_idx < total_len) {
        // Find minimum among current positions
        var min_val: ?T = null;
        var min_idx: usize = 0;

        for (iterables, 0..) |it, i| {
            if (indices[i] < it.len) {
                const val = it[indices[i]];
                if (min_val == null or val < min_val.?) {
                    min_val = val;
                    min_idx = i;
                }
            }
        }

        result[out_idx] = min_val.?;
        indices[min_idx] += 1;
        out_idx += 1;
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "heappush and heappop" {
    const allocator = std.testing.allocator;
    var heap: std.ArrayList(i32) = .empty;
    defer heap.deinit(allocator);

    try heappush(i32, &heap, 5, allocator);
    try heappush(i32, &heap, 3, allocator);
    try heappush(i32, &heap, 7, allocator);
    try heappush(i32, &heap, 1, allocator);

    try std.testing.expectEqual(@as(i32, 1), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 3), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 5), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 7), try heappop(i32, &heap));
}

test "heapify" {
    var arr = [_]i32{ 5, 3, 7, 1, 9, 2 };
    heapify(i32, &arr);

    // First element should be minimum
    try std.testing.expectEqual(@as(i32, 1), arr[0]);
}

test "nsmallest" {
    const allocator = std.testing.allocator;
    const arr = [_]i32{ 5, 3, 7, 1, 9, 2, 8, 4, 6 };

    const result = try nsmallest(i32, 3, &arr, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(i32, 1), result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
    try std.testing.expectEqual(@as(i32, 3), result[2]);
}

test "nlargest" {
    const allocator = std.testing.allocator;
    const arr = [_]i32{ 5, 3, 7, 1, 9, 2, 8, 4, 6 };

    const result = try nlargest(i32, 3, &arr, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(i32, 9), result[0]);
    try std.testing.expectEqual(@as(i32, 8), result[1]);
    try std.testing.expectEqual(@as(i32, 7), result[2]);
}

test "merge" {
    const allocator = std.testing.allocator;
    const a = [_]i32{ 1, 3, 5, 7 };
    const b = [_]i32{ 2, 4, 6, 8 };
    const c = [_]i32{ 0, 9 };

    const iterables = [_][]const i32{ &a, &b, &c };
    const result = try merge(i32, &iterables, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(i32, &[_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, result);
}

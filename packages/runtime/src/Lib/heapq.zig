//! CPython source: Lib/heapq.py
//!
//! Provides an implementation of the heap queue algorithm (priority queue).
//! Heaps are binary trees where parent <= children (min-heap).
//!
//! Mirrors: CPython Lib/heapq.py

const std = @import("std");

/// Push item onto heap, maintaining heap invariant
pub fn heappush(comptime T: type, allocator: std.mem.Allocator, heap: *std.ArrayList(T), item: T) !void {
    try heap.append(allocator, item);
    siftdown(T, heap.items, 0, heap.items.len - 1);
}

/// Pop smallest item from heap, maintaining heap invariant
pub fn heappop(comptime T: type, heap: *std.ArrayList(T)) !T {
    if (heap.items.len == 0) {
        return error.IndexError;
    }

    const last = heap.pop();

    if (heap.items.len > 0) {
        const result = heap.items[0];
        heap.items[0] = last;
        siftup(T, heap.items, 0);
        return result;
    }
    return last;
}

/// Push item, then pop smallest (more efficient than separate operations)
pub fn heappushpop(comptime T: type, heap: *std.ArrayList(T), item: T) T {
    if (heap.items.len > 0 and heap.items[0] < item) {
        const result = heap.items[0];
        heap.items[0] = item;
        siftup(T, heap.items, 0);
        return result;
    }
    return item;
}

/// Pop smallest, then push item (more efficient than separate operations)
pub fn heapreplace(comptime T: type, heap: *std.ArrayList(T), item: T) !T {
    if (heap.items.len == 0) {
        return error.IndexError;
    }

    const result = heap.items[0];
    heap.items[0] = item;
    siftup(T, heap.items, 0);
    return result;
}

/// Transform list into a heap, in-place, in O(n) time
pub fn heapify(comptime T: type, items: []T) void {
    const n = items.len;
    if (n <= 1) return;

    // Start from the last parent node and sift down
    var i = n / 2;
    while (i > 0) {
        i -= 1;
        siftup(T, items, i);
    }
}

/// Return n largest elements from iterable
pub fn nlargest(
    comptime T: type,
    allocator: std.mem.Allocator,
    n: usize,
    items: []const T,
) ![]T {
    if (n == 0 or items.len == 0) {
        return allocator.alloc(T, 0);
    }

    const count = @min(n, items.len);

    // Use a min-heap of size n
    var heap: std.ArrayList(T) = .{};
    defer heap.deinit(allocator);

    for (items) |item| {
        if (heap.items.len < count) {
            try heappush(T, allocator, &heap, item);
        } else if (item > heap.items[0]) {
            _ = heappushpop(T, &heap, item);
        }
    }

    // Extract in reverse order (largest first)
    const result = try allocator.alloc(T, heap.items.len);
    var i = result.len;
    while (i > 0) {
        i -= 1;
        result[i] = try heappop(T, &heap);
    }

    return result;
}

/// Return n smallest elements from iterable
pub fn nsmallest(
    comptime T: type,
    allocator: std.mem.Allocator,
    n: usize,
    items: []const T,
) ![]T {
    if (n == 0 or items.len == 0) {
        return allocator.alloc(T, 0);
    }

    const count = @min(n, items.len);

    // Copy and heapify
    var heap: std.ArrayList(T) = .{};
    defer heap.deinit(allocator);

    for (items) |item| {
        try heap.append(allocator, item);
    }
    heapify(T, heap.items);

    // Extract n smallest
    const result = try allocator.alloc(T, count);
    for (0..count) |i| {
        result[i] = try heappop(T, &heap);
    }

    return result;
}

/// Merge multiple sorted inputs into a single sorted output
pub fn merge(
    comptime T: type,
    allocator: std.mem.Allocator,
    iterables: []const []const T,
) ![]T {
    var total_len: usize = 0;
    for (iterables) |it| {
        total_len += it.len;
    }

    if (total_len == 0) {
        return allocator.alloc(T, 0);
    }

    const result = try allocator.alloc(T, total_len);
    errdefer allocator.free(result);

    // Track current position in each iterable
    const positions = try allocator.alloc(usize, iterables.len);
    defer allocator.free(positions);
    @memset(positions, 0);

    // Build initial heap of (value, source_index) pairs
    const HeapItem = struct {
        value: T,
        source: usize,

        fn lessThan(_: void, a: @This(), b: @This()) bool {
            return a.value < b.value;
        }
    };

    var heap: std.ArrayList(HeapItem) = .{};
    defer heap.deinit(allocator);

    // Initialize heap with first element from each non-empty iterable
    for (iterables, 0..) |it, i| {
        if (it.len > 0) {
            try heappushGeneric(HeapItem, allocator, &heap, .{ .value = it[0], .source = i }, HeapItem.lessThan);
            positions[i] = 1;
        }
    }

    // Merge
    var out_idx: usize = 0;
    while (heap.items.len > 0) {
        const item = try heappopGeneric(HeapItem, &heap, HeapItem.lessThan);
        result[out_idx] = item.value;
        out_idx += 1;

        const source = item.source;
        if (positions[source] < iterables[source].len) {
            try heappushGeneric(HeapItem, allocator, &heap, .{
                .value = iterables[source][positions[source]],
                .source = source,
            }, HeapItem.lessThan);
            positions[source] += 1;
        }
    }

    return result;
}

// ============================================================================
// Internal sift operations
// ============================================================================

fn siftdown(comptime T: type, items: []T, startpos: usize, pos: usize) void {
    var current_pos = pos;
    const newitem = items[current_pos];

    while (current_pos > startpos) {
        const parentpos = (current_pos - 1) >> 1;
        const parent = items[parentpos];
        if (newitem < parent) {
            items[current_pos] = parent;
            current_pos = parentpos;
        } else {
            break;
        }
    }
    items[current_pos] = newitem;
}

fn siftup(comptime T: type, items: []T, pos: usize) void {
    const endpos = items.len;
    const startpos = pos;
    const newitem = items[pos];

    var childpos = 2 * pos + 1;
    var current_pos = pos;

    while (childpos < endpos) {
        const rightpos = childpos + 1;
        if (rightpos < endpos and !(items[childpos] < items[rightpos])) {
            childpos = rightpos;
        }
        items[current_pos] = items[childpos];
        current_pos = childpos;
        childpos = 2 * current_pos + 1;
    }

    items[current_pos] = newitem;
    siftdown(T, items, startpos, current_pos);
}

// Generic versions with custom comparator
fn heappushGeneric(
    comptime T: type,
    allocator: std.mem.Allocator,
    heap: *std.ArrayList(T),
    item: T,
    comptime lessThan: fn (void, T, T) bool,
) !void {
    try heap.append(allocator, item);
    siftdownGeneric(T, heap.items, 0, heap.items.len - 1, lessThan);
}

fn heappopGeneric(
    comptime T: type,
    heap: *std.ArrayList(T),
    comptime lessThan: fn (void, T, T) bool,
) !T {
    if (heap.items.len == 0) {
        return error.IndexError;
    }

    const last = heap.pop();

    if (heap.items.len > 0) {
        const result = heap.items[0];
        heap.items[0] = last;
        siftupGeneric(T, heap.items, 0, lessThan);
        return result;
    }
    return last;
}

fn siftdownGeneric(
    comptime T: type,
    items: []T,
    startpos: usize,
    pos: usize,
    comptime lessThan: fn (void, T, T) bool,
) void {
    var current_pos = pos;
    const newitem = items[current_pos];

    while (current_pos > startpos) {
        const parentpos = (current_pos - 1) >> 1;
        const parent = items[parentpos];
        if (lessThan({}, newitem, parent)) {
            items[current_pos] = parent;
            current_pos = parentpos;
        } else {
            break;
        }
    }
    items[current_pos] = newitem;
}

fn siftupGeneric(
    comptime T: type,
    items: []T,
    pos: usize,
    comptime lessThan: fn (void, T, T) bool,
) void {
    const endpos = items.len;
    const startpos = pos;
    const newitem = items[pos];

    var childpos = 2 * pos + 1;
    var current_pos = pos;

    while (childpos < endpos) {
        const rightpos = childpos + 1;
        if (rightpos < endpos and !lessThan({}, items[childpos], items[rightpos])) {
            childpos = rightpos;
        }
        items[current_pos] = items[childpos];
        current_pos = childpos;
        childpos = 2 * current_pos + 1;
    }

    items[current_pos] = newitem;
    siftdownGeneric(T, items, startpos, current_pos, lessThan);
}

// ============================================================================
// Tests
// ============================================================================

test "heappush and heappop" {
    const allocator = std.testing.allocator;
    var heap: std.ArrayList(i32) = .{};
    defer heap.deinit(allocator);

    try heappush(i32, allocator, &heap, 5);
    try heappush(i32, allocator, &heap, 3);
    try heappush(i32, allocator, &heap, 7);
    try heappush(i32, allocator, &heap, 1);

    try std.testing.expectEqual(@as(i32, 1), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 3), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 5), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 7), try heappop(i32, &heap));
}

test "heapify" {
    var items = [_]i32{ 5, 3, 7, 1, 4, 6, 2 };
    heapify(i32, &items);

    // After heapify, root should be minimum
    try std.testing.expectEqual(@as(i32, 1), items[0]);

    // Verify heap property
    for (0..items.len) |i| {
        const left = 2 * i + 1;
        const right = 2 * i + 2;
        if (left < items.len) {
            try std.testing.expect(items[i] <= items[left]);
        }
        if (right < items.len) {
            try std.testing.expect(items[i] <= items[right]);
        }
    }
}

test "heappushpop" {
    const allocator = std.testing.allocator;
    var heap: std.ArrayList(i32) = .{};
    defer heap.deinit(allocator);

    try heappush(i32, allocator, &heap, 5);
    try heappush(i32, allocator, &heap, 3);

    // Push 1, should return 1 immediately (smaller than heap min)
    try std.testing.expectEqual(@as(i32, 1), heappushpop(i32, &heap, 1));

    // Push 10, should return 3 (current min) and push 10
    try std.testing.expectEqual(@as(i32, 3), heappushpop(i32, &heap, 10));
}

test "heapreplace" {
    const allocator = std.testing.allocator;
    var heap: std.ArrayList(i32) = .{};
    defer heap.deinit(allocator);

    try heappush(i32, allocator, &heap, 5);
    try heappush(i32, allocator, &heap, 3);

    // Replace min (3) with 10
    try std.testing.expectEqual(@as(i32, 3), try heapreplace(i32, &heap, 10));
    try std.testing.expectEqual(@as(i32, 5), try heappop(i32, &heap));
    try std.testing.expectEqual(@as(i32, 10), try heappop(i32, &heap));
}

test "nlargest" {
    const allocator = std.testing.allocator;
    const items = [_]i32{ 5, 3, 7, 1, 4, 6, 2 };

    const result = try nlargest(i32, allocator, 3, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(i32, 7), result[0]);
    try std.testing.expectEqual(@as(i32, 6), result[1]);
    try std.testing.expectEqual(@as(i32, 5), result[2]);
}

test "nsmallest" {
    const allocator = std.testing.allocator;
    const items = [_]i32{ 5, 3, 7, 1, 4, 6, 2 };

    const result = try nsmallest(i32, allocator, 3, &items);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(i32, 1), result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
    try std.testing.expectEqual(@as(i32, 3), result[2]);
}

test "merge" {
    const allocator = std.testing.allocator;
    const a = [_]i32{ 1, 3, 5 };
    const b = [_]i32{ 2, 4, 6 };
    const c = [_]i32{ 0, 7 };

    const iterables = [_][]const i32{ &a, &b, &c };
    const result = try merge(i32, allocator, &iterables);
    defer allocator.free(result);

    const expected = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7 };
    try std.testing.expectEqualSlices(i32, &expected, result);
}

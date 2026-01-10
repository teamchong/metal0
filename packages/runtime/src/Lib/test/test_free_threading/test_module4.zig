//! test.test_free_threading.test_list - Concurrent list operations
//!
//! This module provides thread-safe list implementations and tests for
//! concurrent list operations in free-threaded Python execution.
const std = @import("std");

/// Thread-safe dynamic array with mutex protection
pub fn ConcurrentList(comptime T: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        version: std.atomic.Value(usize),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .mutex = .{},
                .version = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.deinit();
        }

        pub fn append(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(item);
            _ = self.version.fetchAdd(1, .release);
        }

        pub fn appendSlice(self: *Self, items: []const T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.appendSlice(items);
            _ = self.version.fetchAdd(1, .release);
        }

        pub fn get(self: *Self, index: usize) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (index >= self.items.items.len) return null;
            return self.items.items[index];
        }

        pub fn set(self: *Self, index: usize, value: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (index >= self.items.items.len) return false;
            self.items.items[index] = value;
            _ = self.version.fetchAdd(1, .release);
            return true;
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            const result = self.items.popOrNull();
            if (result != null) {
                _ = self.version.fetchAdd(1, .release);
            }
            return result;
        }

        pub fn insert(self: *Self, index: usize, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.insert(index, item);
            _ = self.version.fetchAdd(1, .release);
        }

        pub fn remove(self: *Self, index: usize) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (index >= self.items.items.len) return null;
            const item = self.items.orderedRemove(index);
            _ = self.version.fetchAdd(1, .release);
            return item;
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.clearRetainingCapacity();
            _ = self.version.fetchAdd(1, .release);
        }

        pub fn getVersion(self: *const Self) usize {
            return self.version.load(.acquire);
        }

        pub fn toOwnedSlice(self: *Self, allocator: std.mem.Allocator) ![]T {
            self.mutex.lock();
            defer self.mutex.unlock();
            const result = try allocator.alloc(T, self.items.items.len);
            @memcpy(result, self.items.items);
            return result;
        }
    };
}

/// Lock-free append-only list using atomic operations
pub fn AppendOnlyList(comptime T: type, comptime max_size: usize) type {
    return struct {
        const Self = @This();

        data: [max_size]T,
        len: std.atomic.Value(usize),

        pub fn init() Self {
            return .{
                .data = undefined,
                .len = std.atomic.Value(usize).init(0),
            };
        }

        pub fn append(self: *Self, item: T) bool {
            while (true) {
                const current_len = self.len.load(.acquire);
                if (current_len >= max_size) {
                    return false; // List full
                }

                if (self.len.cmpxchgWeak(current_len, current_len + 1, .release, .acquire)) |_| {
                    continue; // Retry
                }

                self.data[current_len] = item;
                return true;
            }
        }

        pub fn get(self: *const Self, index: usize) ?T {
            const current_len = self.len.load(.acquire);
            if (index >= current_len) return null;
            return self.data[index];
        }

        pub fn length(self: *const Self) usize {
            return self.len.load(.acquire);
        }

        pub fn isFull(self: *const Self) bool {
            return self.len.load(.acquire) >= max_size;
        }
    };
}

/// Segmented list for reduced contention
pub fn SegmentedList(comptime T: type) type {
    return struct {
        const Self = @This();
        const SEGMENT_SIZE = 64;

        const Segment = struct {
            data: [SEGMENT_SIZE]T,
            len: usize,
            next: ?*Segment,
            mutex: std.Thread.Mutex,

            fn init() Segment {
                return .{
                    .data = undefined,
                    .len = 0,
                    .next = null,
                    .mutex = .{},
                };
            }
        };

        head: ?*Segment,
        tail: *Segment,
        allocator: std.mem.Allocator,
        total_len: std.atomic.Value(usize),
        segment_count: std.atomic.Value(usize),
        global_mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const segment = try allocator.create(Segment);
            segment.* = Segment.init();
            return .{
                .head = segment,
                .tail = segment,
                .allocator = allocator,
                .total_len = std.atomic.Value(usize).init(0),
                .segment_count = std.atomic.Value(usize).init(1),
                .global_mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.global_mutex.lock();
            defer self.global_mutex.unlock();

            var current = self.head;
            while (current) |segment| {
                const next = segment.next;
                self.allocator.destroy(segment);
                current = next;
            }
        }

        pub fn append(self: *Self, item: T) !void {
            self.global_mutex.lock();
            defer self.global_mutex.unlock();

            if (self.tail.len >= SEGMENT_SIZE) {
                const new_segment = try self.allocator.create(Segment);
                new_segment.* = Segment.init();
                self.tail.next = new_segment;
                self.tail = new_segment;
                _ = self.segment_count.fetchAdd(1, .monotonic);
            }

            self.tail.data[self.tail.len] = item;
            self.tail.len += 1;
            _ = self.total_len.fetchAdd(1, .release);
        }

        pub fn get(self: *Self, index: usize) ?T {
            self.global_mutex.lock();
            defer self.global_mutex.unlock();

            if (index >= self.total_len.load(.acquire)) return null;

            var remaining = index;
            var current = self.head;

            while (current) |segment| {
                if (remaining < segment.len) {
                    return segment.data[remaining];
                }
                remaining -= segment.len;
                current = segment.next;
            }

            return null;
        }

        pub fn len(self: *const Self) usize {
            return self.total_len.load(.acquire);
        }

        pub fn segmentCount(self: *const Self) usize {
            return self.segment_count.load(.acquire);
        }
    };
}

/// Concurrent sorted list using skip list-like structure
pub fn ConcurrentSortedList(comptime T: type, comptime compareFn: fn (T, T) std.math.Order) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.items.deinit();
        }

        pub fn insert(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Binary search for insertion point
            var low: usize = 0;
            var high: usize = self.items.items.len;

            while (low < high) {
                const mid = low + (high - low) / 2;
                if (compareFn(self.items.items[mid], item) == .lt) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }

            try self.items.insert(low, item);
        }

        pub fn contains(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            var low: usize = 0;
            var high: usize = self.items.items.len;

            while (low < high) {
                const mid = low + (high - low) / 2;
                const cmp = compareFn(self.items.items[mid], item);
                if (cmp == .eq) return true;
                if (cmp == .lt) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }

            return false;
        }

        pub fn remove(self: *Self, item: T) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            var low: usize = 0;
            var high: usize = self.items.items.len;

            while (low < high) {
                const mid = low + (high - low) / 2;
                const cmp = compareFn(self.items.items[mid], item);
                if (cmp == .eq) {
                    _ = self.items.orderedRemove(mid);
                    return true;
                }
                if (cmp == .lt) {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }

            return false;
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        pub fn min(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        pub fn max(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }
    };
}

/// Batch operation helper for lists
pub fn BatchOperations(comptime T: type) type {
    return struct {
        const Self = @This();

        operations: std.ArrayList(Operation),
        allocator: std.mem.Allocator,

        const OperationType = enum { append, remove, set };
        const Operation = struct {
            op_type: OperationType,
            index: ?usize,
            value: T,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .operations = std.ArrayList(Operation).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.operations.deinit();
        }

        pub fn addAppend(self: *Self, value: T) !void {
            try self.operations.append(.{
                .op_type = .append,
                .index = null,
                .value = value,
            });
        }

        pub fn addRemove(self: *Self, index: usize, default: T) !void {
            try self.operations.append(.{
                .op_type = .remove,
                .index = index,
                .value = default,
            });
        }

        pub fn addSet(self: *Self, index: usize, value: T) !void {
            try self.operations.append(.{
                .op_type = .set,
                .index = index,
                .value = value,
            });
        }

        pub fn apply(self: *Self, list: *ConcurrentList(T)) !void {
            list.mutex.lock();
            defer list.mutex.unlock();

            for (self.operations.items) |op| {
                switch (op.op_type) {
                    .append => try list.items.append(op.value),
                    .remove => {
                        if (op.index) |idx| {
                            if (idx < list.items.items.len) {
                                _ = list.items.orderedRemove(idx);
                            }
                        }
                    },
                    .set => {
                        if (op.index) |idx| {
                            if (idx < list.items.items.len) {
                                list.items.items[idx] = op.value;
                            }
                        }
                    },
                }
            }
            _ = list.version.fetchAdd(1, .release);
        }

        pub fn clear(self: *Self) void {
            self.operations.clearRetainingCapacity();
        }
    };
}

/// List iterator with version checking for concurrent modification detection
pub fn VersionedIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        list: *ConcurrentList(T),
        index: usize,
        initial_version: usize,

        pub fn init(list: *ConcurrentList(T)) Self {
            return .{
                .list = list,
                .index = 0,
                .initial_version = list.getVersion(),
            };
        }

        pub fn next(self: *Self) error{ConcurrentModification}!?T {
            if (self.list.getVersion() != self.initial_version) {
                return error.ConcurrentModification;
            }

            const item = self.list.get(self.index);
            if (item != null) {
                self.index += 1;
            }
            return item;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
            self.initial_version = self.list.getVersion();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "concurrent_list_basic" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expectEqual(@as(?i32, 1), list.get(0));
    try std.testing.expectEqual(@as(?i32, 2), list.get(1));
    try std.testing.expectEqual(@as(?i32, 3), list.get(2));
    try std.testing.expectEqual(@as(?i32, null), list.get(10));
}

test "concurrent_list_pop" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    try list.append(10);
    try list.append(20);
    try list.append(30);

    try std.testing.expectEqual(@as(?i32, 30), list.pop());
    try std.testing.expectEqual(@as(?i32, 20), list.pop());
    try std.testing.expectEqual(@as(usize, 1), list.len());
}

test "concurrent_list_set" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);

    try std.testing.expect(list.set(1, 42));
    try std.testing.expectEqual(@as(?i32, 42), list.get(1));
    try std.testing.expect(!list.set(10, 100));
}

test "concurrent_list_insert_remove" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(3);
    try list.insert(1, 2);

    try std.testing.expectEqual(@as(?i32, 1), list.get(0));
    try std.testing.expectEqual(@as(?i32, 2), list.get(1));
    try std.testing.expectEqual(@as(?i32, 3), list.get(2));

    try std.testing.expectEqual(@as(?i32, 2), list.remove(1));
    try std.testing.expectEqual(@as(usize, 2), list.len());
}

test "append_only_list_basic" {
    var list = AppendOnlyList(i32, 8).init();

    try std.testing.expect(list.append(1));
    try std.testing.expect(list.append(2));
    try std.testing.expect(list.append(3));

    try std.testing.expectEqual(@as(usize, 3), list.length());
    try std.testing.expectEqual(@as(?i32, 1), list.get(0));
    try std.testing.expectEqual(@as(?i32, 2), list.get(1));
    try std.testing.expectEqual(@as(?i32, 3), list.get(2));
}

test "append_only_list_full" {
    var list = AppendOnlyList(i32, 3).init();

    try std.testing.expect(list.append(1));
    try std.testing.expect(list.append(2));
    try std.testing.expect(list.append(3));
    try std.testing.expect(!list.append(4)); // Should fail

    try std.testing.expect(list.isFull());
}

test "segmented_list_basic" {
    const allocator = std.testing.allocator;
    var list = try SegmentedList(i32).init(allocator);
    defer list.deinit();

    for (0..100) |i| {
        try list.append(@intCast(i));
    }

    try std.testing.expectEqual(@as(usize, 100), list.len());
    try std.testing.expectEqual(@as(?i32, 0), list.get(0));
    try std.testing.expectEqual(@as(?i32, 50), list.get(50));
    try std.testing.expectEqual(@as(?i32, 99), list.get(99));

    // Should have created 2 segments (64 + 36)
    try std.testing.expectEqual(@as(usize, 2), list.segmentCount());
}

fn compareI32(a: i32, b: i32) std.math.Order {
    if (a < b) return .lt;
    if (a > b) return .gt;
    return .eq;
}

test "concurrent_sorted_list_basic" {
    const allocator = std.testing.allocator;
    var list = ConcurrentSortedList(i32, compareI32).init(allocator);
    defer list.deinit();

    try list.insert(5);
    try list.insert(2);
    try list.insert(8);
    try list.insert(1);
    try list.insert(9);

    try std.testing.expectEqual(@as(?i32, 1), list.min());
    try std.testing.expectEqual(@as(?i32, 9), list.max());
    try std.testing.expect(list.contains(5));
    try std.testing.expect(!list.contains(6));
}

test "concurrent_sorted_list_remove" {
    const allocator = std.testing.allocator;
    var list = ConcurrentSortedList(i32, compareI32).init(allocator);
    defer list.deinit();

    try list.insert(1);
    try list.insert(2);
    try list.insert(3);

    try std.testing.expect(list.remove(2));
    try std.testing.expect(!list.contains(2));
    try std.testing.expectEqual(@as(usize, 2), list.len());
}

test "batch_operations_basic" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    var batch = BatchOperations(i32).init(allocator);
    defer batch.deinit();

    try batch.addAppend(1);
    try batch.addAppend(2);
    try batch.addAppend(3);
    try batch.apply(&list);

    try std.testing.expectEqual(@as(usize, 3), list.len());
    try std.testing.expectEqual(@as(?i32, 1), list.get(0));
}

test "versioned_iterator_basic" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    var iter = VersionedIterator(i32).init(&list);

    try std.testing.expectEqual(@as(?i32, 1), try iter.next());
    try std.testing.expectEqual(@as(?i32, 2), try iter.next());
    try std.testing.expectEqual(@as(?i32, 3), try iter.next());
    try std.testing.expectEqual(@as(?i32, null), try iter.next());
}

test "concurrent_list_multithread" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(usize).init(allocator);
    defer list.deinit();

    const num_threads = 4;
    const items_per_thread = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(l: *ConcurrentList(usize), tid: usize) void {
                for (0..items_per_thread) |j| {
                    l.append(tid * items_per_thread + j) catch {};
                }
            }
        }.run, .{ &list, i }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(usize, num_threads * items_per_thread), list.len());
}

test "concurrent_list_version_tracking" {
    const allocator = std.testing.allocator;
    var list = ConcurrentList(i32).init(allocator);
    defer list.deinit();

    const v1 = list.getVersion();
    try list.append(1);
    const v2 = list.getVersion();
    try list.append(2);
    const v3 = list.getVersion();

    try std.testing.expect(v2 > v1);
    try std.testing.expect(v3 > v2);
}

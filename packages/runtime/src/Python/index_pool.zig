/// index_pool - Index Pool for Free-Threading
/// Mirrors cpython/Python/index_pool.c
///
/// This module provides an index pool for managing unique indices:
/// - Thread-safe index allocation and deallocation
/// - Efficient reuse of freed indices
/// - Used for thread-local storage and per-thread data

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Initial capacity of the pool
const INITIAL_CAPACITY: usize = 16;

/// Growth factor when pool needs to expand
const GROWTH_FACTOR: usize = 2;

/// Invalid index marker
pub const INVALID_INDEX: usize = std.math.maxInt(usize);

// ============================================================================
// Index Pool
// ============================================================================

/// Thread-safe pool of reusable indices
pub const IndexPool = struct {
    /// Free list of available indices
    free_list: std.ArrayList(usize),
    /// Next index to allocate if free list is empty
    next_index: std.atomic.Value(usize),
    /// Maximum allocated index
    max_index: std.atomic.Value(usize),
    /// Lock for thread safety
    mutex: std.Thread.Mutex,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    /// Initialize a new index pool
    pub fn init(allocator: Allocator) Self {
        return .{
            .free_list = std.ArrayList(usize).init(allocator),
            .next_index = std.atomic.Value(usize).init(0),
            .max_index = std.atomic.Value(usize).init(0),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    /// Deinitialize the pool
    pub fn deinit(self: *Self) void {
        self.free_list.deinit();
    }

    /// Allocate an index from the pool
    pub fn alloc(self: *Self) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to reuse from free list
        if (self.free_list.popOrNull()) |index| {
            return index;
        }

        // Allocate new index
        const index = self.next_index.fetchAdd(1, .monotonic);

        // Update max if needed
        var current_max = self.max_index.load(.monotonic);
        while (index > current_max) {
            const result = self.max_index.cmpxchgWeak(
                current_max,
                index,
                .monotonic,
                .monotonic,
            );
            if (result) |new_max| {
                current_max = new_max;
            } else {
                break;
            }
        }

        return index;
    }

    /// Free an index back to the pool
    pub fn free(self: *Self, index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.free_list.append(index) catch {
            // If append fails, the index is lost but that's acceptable
            // for correctness (just suboptimal for reuse)
        };
    }

    /// Get number of indices in free list
    pub fn freeCount(self: *const Self) usize {
        return self.free_list.items.len;
    }

    /// Get the next index that would be allocated
    pub fn getNextIndex(self: *const Self) usize {
        return self.next_index.load(.monotonic);
    }

    /// Get the maximum allocated index
    pub fn getMaxIndex(self: *const Self) usize {
        return self.max_index.load(.monotonic);
    }

    /// Check if an index is valid (was allocated)
    pub fn isValid(self: *const Self, index: usize) bool {
        return index < self.next_index.load(.monotonic);
    }

    /// Reset the pool (not thread-safe, for testing)
    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.free_list.clearRetainingCapacity();
        self.next_index.store(0, .monotonic);
        self.max_index.store(0, .monotonic);
    }
};

// ============================================================================
// Compact Index Pool
// ============================================================================

/// A more memory-efficient pool using a bitmap
pub const CompactIndexPool = struct {
    /// Bitmap of used indices (1 = used, 0 = free)
    bitmap: std.DynamicBitSet,
    /// Number of indices in use
    in_use: std.atomic.Value(usize),
    /// Hint for next free index search
    search_hint: usize,
    /// Lock for thread safety
    mutex: std.Thread.Mutex,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    /// Initialize with initial capacity
    pub fn init(allocator: Allocator, initial_capacity: usize) !Self {
        var bitmap = try std.DynamicBitSet.initEmpty(allocator, initial_capacity);
        return .{
            .bitmap = bitmap,
            .in_use = std.atomic.Value(usize).init(0),
            .search_hint = 0,
            .mutex = .{},
            .allocator = allocator,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.bitmap.deinit();
    }

    /// Allocate an index
    pub fn alloc(self: *Self) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Search from hint
        var index = self.search_hint;
        const capacity = self.bitmap.capacity();

        // Search for free slot
        while (index < capacity) {
            if (!self.bitmap.isSet(index)) {
                self.bitmap.set(index);
                _ = self.in_use.fetchAdd(1, .monotonic);
                self.search_hint = index + 1;
                return index;
            }
            index += 1;
        }

        // Search from beginning
        index = 0;
        while (index < self.search_hint) {
            if (!self.bitmap.isSet(index)) {
                self.bitmap.set(index);
                _ = self.in_use.fetchAdd(1, .monotonic);
                self.search_hint = index + 1;
                return index;
            }
            index += 1;
        }

        // Need to grow
        const new_capacity = if (capacity == 0) INITIAL_CAPACITY else capacity * GROWTH_FACTOR;
        try self.bitmap.resize(new_capacity, false);

        // Allocate at old capacity position
        self.bitmap.set(capacity);
        _ = self.in_use.fetchAdd(1, .monotonic);
        self.search_hint = capacity + 1;
        return capacity;
    }

    /// Free an index
    pub fn free(self: *Self, index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index < self.bitmap.capacity() and self.bitmap.isSet(index)) {
            self.bitmap.unset(index);
            _ = self.in_use.fetchSub(1, .monotonic);
            // Update hint if this is lower
            if (index < self.search_hint) {
                self.search_hint = index;
            }
        }
    }

    /// Get number of indices in use
    pub fn inUseCount(self: *const Self) usize {
        return self.in_use.load(.monotonic);
    }

    /// Check if index is in use
    pub fn isInUse(self: *const Self, index: usize) bool {
        if (index >= self.bitmap.capacity()) return false;
        return self.bitmap.isSet(index);
    }

    /// Get capacity
    pub fn capacity(self: *const Self) usize {
        return self.bitmap.capacity();
    }
};

// ============================================================================
// Lock-Free Index Pool (for high concurrency)
// ============================================================================

/// Lock-free index pool using atomic operations
pub const LockFreeIndexPool = struct {
    /// Head of free list (index, or INVALID for empty)
    free_head: std.atomic.Value(usize),
    /// Next index to allocate
    next_index: std.atomic.Value(usize),
    /// Free list next pointers (sparse array)
    free_next: []std.atomic.Value(usize),
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    /// Initialize with maximum capacity
    pub fn init(allocator: Allocator, max_capacity: usize) !Self {
        const free_next = try allocator.alloc(std.atomic.Value(usize), max_capacity);
        for (free_next) |*slot| {
            slot.* = std.atomic.Value(usize).init(INVALID_INDEX);
        }
        return .{
            .free_head = std.atomic.Value(usize).init(INVALID_INDEX),
            .next_index = std.atomic.Value(usize).init(0),
            .free_next = free_next,
            .allocator = allocator,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.free_next);
    }

    /// Allocate an index (lock-free)
    pub fn alloc(self: *Self) !usize {
        // Try to pop from free list
        while (true) {
            const head = self.free_head.load(.acquire);
            if (head == INVALID_INDEX) break;

            // Get next in free list
            const next = self.free_next[head].load(.acquire);

            // Try to update head
            if (self.free_head.cmpxchgWeak(head, next, .release, .monotonic) == null) {
                return head;
            }
            // CAS failed, retry
        }

        // Free list empty, allocate new
        const index = self.next_index.fetchAdd(1, .monotonic);
        if (index >= self.free_next.len) {
            return error.PoolExhausted;
        }
        return index;
    }

    /// Free an index (lock-free)
    pub fn free(self: *Self, index: usize) void {
        if (index >= self.free_next.len) return;

        // Push onto free list
        while (true) {
            const head = self.free_head.load(.acquire);
            self.free_next[index].store(head, .release);

            if (self.free_head.cmpxchgWeak(index, head, .release, .monotonic) == null) {
                return;
            }
            // CAS failed, retry
        }
    }

    /// Get next index that would be allocated (approximate)
    pub fn getNextIndex(self: *const Self) usize {
        return self.next_index.load(.monotonic);
    }
};

// ============================================================================
// Global Pool Instance
// ============================================================================

var global_pool: ?IndexPool = null;

/// Initialize global pool
pub fn initGlobalPool(allocator: Allocator) void {
    if (global_pool == null) {
        global_pool = IndexPool.init(allocator);
    }
}

/// Get global pool (initialize with default if needed)
pub fn getGlobalPool() *IndexPool {
    if (global_pool == null) {
        global_pool = IndexPool.init(allocator_helper.fast_allocator);
    }
    return &global_pool.?;
}

/// Allocate from global pool
pub fn globalAlloc() !usize {
    return getGlobalPool().alloc();
}

/// Free to global pool
pub fn globalFree(index: usize) void {
    getGlobalPool().free(index);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "index pool basic" {
    var pool = IndexPool.init(std.testing.allocator);
    defer pool.deinit();

    const i0 = try pool.alloc();
    const i1 = try pool.alloc();
    const i2 = try pool.alloc();

    try std.testing.expectEqual(@as(usize, 0), i0);
    try std.testing.expectEqual(@as(usize, 1), i1);
    try std.testing.expectEqual(@as(usize, 2), i2);

    pool.free(i1);
    try std.testing.expectEqual(@as(usize, 1), pool.freeCount());

    const i3 = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 1), i3); // Reused

    try std.testing.expectEqual(@as(usize, 0), pool.freeCount());
}

test "index pool validity" {
    var pool = IndexPool.init(std.testing.allocator);
    defer pool.deinit();

    try std.testing.expect(!pool.isValid(0));
    try std.testing.expect(!pool.isValid(100));

    _ = try pool.alloc();
    try std.testing.expect(pool.isValid(0));
    try std.testing.expect(!pool.isValid(1));

    _ = try pool.alloc();
    try std.testing.expect(pool.isValid(1));
}

test "compact index pool" {
    var pool = try CompactIndexPool.init(std.testing.allocator, 8);
    defer pool.deinit();

    const i0 = try pool.alloc();
    const i1 = try pool.alloc();

    try std.testing.expectEqual(@as(usize, 0), i0);
    try std.testing.expectEqual(@as(usize, 1), i1);
    try std.testing.expectEqual(@as(usize, 2), pool.inUseCount());

    try std.testing.expect(pool.isInUse(0));
    try std.testing.expect(pool.isInUse(1));
    try std.testing.expect(!pool.isInUse(2));

    pool.free(i0);
    try std.testing.expect(!pool.isInUse(0));
    try std.testing.expectEqual(@as(usize, 1), pool.inUseCount());

    const i2 = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 0), i2); // Reused
}

test "compact index pool growth" {
    var pool = try CompactIndexPool.init(std.testing.allocator, 2);
    defer pool.deinit();

    _ = try pool.alloc(); // 0
    _ = try pool.alloc(); // 1
    const i2 = try pool.alloc(); // Should trigger growth

    try std.testing.expectEqual(@as(usize, 2), i2);
    try std.testing.expect(pool.capacity() > 2);
}

test "lock-free index pool" {
    var pool = try LockFreeIndexPool.init(std.testing.allocator, 100);
    defer pool.deinit();

    const i0 = try pool.alloc();
    const i1 = try pool.alloc();
    const i2 = try pool.alloc();

    try std.testing.expectEqual(@as(usize, 0), i0);
    try std.testing.expectEqual(@as(usize, 1), i1);
    try std.testing.expectEqual(@as(usize, 2), i2);

    pool.free(i1);

    const i3 = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 1), i3); // Reused
}

test "index pool reset" {
    var pool = IndexPool.init(std.testing.allocator);
    defer pool.deinit();

    _ = try pool.alloc();
    _ = try pool.alloc();
    pool.free(0);

    pool.reset();

    try std.testing.expectEqual(@as(usize, 0), pool.getNextIndex());
    try std.testing.expectEqual(@as(usize, 0), pool.freeCount());

    const i0 = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 0), i0);
}

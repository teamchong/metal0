const std = @import("std");

/// Object pool for fixed-size allocations
///
/// Inspired by Tokio's object pool pattern for common async primitives.
/// Pre-allocates objects and reuses them, avoiding repeated allocations.
///
/// Benefits:
/// - Near-zero allocation overhead (just free list lookup)
/// - Excellent cache locality (objects in contiguous array)
/// - Predictable performance (no malloc/free calls)
/// - Thread-safe with minimal lock contention
pub fn Pool(comptime T: type, comptime capacity: usize) type {
    return struct {
        /// Pre-allocated objects
        objects: [capacity]T,

        /// Free list (true = available, false = in use)
        free_list: [capacity]bool,

        /// Mutex for thread-safe access
        mutex: std.Thread.Mutex,

        /// Statistics
        total_acquired: u64,
        total_released: u64,
        peak_usage: usize,
        current_usage: usize,

        const Self = @This();

        /// Initialize pool
        pub fn init() Self {
            return Self{
                .objects = undefined,
                .free_list = [_]bool{true} ** capacity,
                .mutex = std.Thread.Mutex{},
                .total_acquired = 0,
                .total_released = 0,
                .peak_usage = 0,
                .current_usage = 0,
            };
        }

        /// Acquire object from pool
        pub fn acquire(self: *Self) ?*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Find first available object
            for (&self.free_list, 0..) |*free, i| {
                if (free.*) {
                    free.* = false;
                    self.total_acquired += 1;
                    self.current_usage += 1;

                    if (self.current_usage > self.peak_usage) {
                        self.peak_usage = self.current_usage;
                    }

                    return &self.objects[i];
                }
            }

            // Pool exhausted
            return null;
        }

        /// Release object back to pool
        pub fn release(self: *Self, obj: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Calculate index
            const index = (@intFromPtr(obj) - @intFromPtr(&self.objects[0])) / @sizeOf(T);

            // Mark as available
            self.free_list[index] = true;
            self.total_released += 1;
            self.current_usage -= 1;
        }

        /// Get number of available objects
        pub fn available(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return capacity - self.current_usage;
        }

        /// Get pool statistics
        pub fn stats(self: *Self) PoolStats {
            self.mutex.lock();
            defer self.mutex.unlock();

            return PoolStats{
                .capacity = capacity,
                .in_use = self.current_usage,
                .available_count = capacity - self.current_usage,
                .total_acquired = self.total_acquired,
                .total_released = self.total_released,
                .peak_usage = self.peak_usage,
            };
        }

        /// Reset pool (mark all as available)
        pub fn reset(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.free_list = [_]bool{true} ** capacity;
            self.current_usage = 0;
        }
    };
}

/// Pool statistics
pub const PoolStats = struct {
    capacity: usize,
    in_use: usize,
    available_count: usize,
    total_acquired: u64,
    total_released: u64,
    peak_usage: usize,

    /// Utilization percentage
    pub fn utilization(self: PoolStats) f64 {
        return @as(f64, @floatFromInt(self.in_use)) / @as(f64, @floatFromInt(self.capacity)) * 100.0;
    }

    /// Peak utilization percentage
    pub fn peakUtilization(self: PoolStats) f64 {
        return @as(f64, @floatFromInt(self.peak_usage)) / @as(f64, @floatFromInt(self.capacity)) * 100.0;
    }
};

/// Dynamic object pool (grows as needed)
///
/// Unlike fixed-size Pool, this can allocate additional objects
/// beyond the initial capacity when pool is exhausted.
pub fn DynamicPool(comptime T: type, comptime initial_capacity: usize) type {
    return struct {
        /// Static pool
        static_pool: Pool(T, initial_capacity),

        /// Overflow allocations
        overflow: std.ArrayList(*T),

        /// Backing allocator for overflow
        allocator: std.mem.Allocator,

        /// Overflow statistics
        total_overflow: u64,

        const Self = @This();

        /// Initialize dynamic pool
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .static_pool = Pool(T, initial_capacity).init(),
                .overflow = std.ArrayList(*T){},
                .allocator = allocator,
                .total_overflow = 0,
            };
        }

        /// Clean up dynamic pool
        pub fn deinit(self: *Self) void {
            // Free overflow allocations
            for (self.overflow.items) |obj| {
                self.allocator.destroy(obj);
            }
            self.overflow.deinit(self.allocator);
        }

        /// Acquire object (from pool or allocate new)
        pub fn acquire(self: *Self) !*T {
            // Try static pool first
            if (self.static_pool.acquire()) |obj| {
                return obj;
            }

            // Try overflow pool
            {
                self.static_pool.mutex.lock();
                defer self.static_pool.mutex.unlock();

                if (self.overflow.items.len > 0) {
                    return self.overflow.pop();
                }
            }

            // Allocate new object
            const obj = try self.allocator.create(T);
            self.total_overflow += 1;
            return obj;
        }

        /// Release object back to pool
        pub fn release(self: *Self, obj: *T) !void {
            // Check if it's from static pool
            const base = @intFromPtr(&self.static_pool.objects[0]);
            const end = base + @sizeOf(T) * initial_capacity;
            const addr = @intFromPtr(obj);

            if (addr >= base and addr < end) {
                // From static pool
                self.static_pool.release(obj);
            } else {
                // Overflow object - return to overflow pool
                self.static_pool.mutex.lock();
                defer self.static_pool.mutex.unlock();

                try self.overflow.append(self.allocator, obj);
            }
        }

        /// Get combined statistics
        pub fn stats(self: *Self) DynamicPoolStats {
            const static_stats = self.static_pool.stats();

            self.static_pool.mutex.lock();
            defer self.static_pool.mutex.unlock();

            return DynamicPoolStats{
                .static_capacity = static_stats.capacity,
                .static_in_use = static_stats.in_use,
                .overflow_available = self.overflow.items.len,
                .total_overflow = self.total_overflow,
                .total_acquired = static_stats.total_acquired,
                .total_released = static_stats.total_released,
            };
        }
    };
}

/// Dynamic pool statistics
pub const DynamicPoolStats = struct {
    static_capacity: usize,
    static_in_use: usize,
    overflow_available: usize,
    total_overflow: u64,
    total_acquired: u64,
    total_released: u64,

    /// Total available objects
    pub fn totalAvailable(self: DynamicPoolStats) usize {
        return (self.static_capacity - self.static_in_use) + self.overflow_available;
    }
};

// Tests
const testing = std.testing;

test "Pool init" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    try testing.expectEqual(@as(usize, 10), pool.available());
}

test "Pool acquire/release" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    // Acquire
    const obj1 = pool.acquire().?;
    obj1.* = 42;
    try testing.expectEqual(@as(u32, 42), obj1.*);
    try testing.expectEqual(@as(usize, 9), pool.available());

    // Acquire another
    const obj2 = pool.acquire().?;
    obj2.* = 84;
    try testing.expectEqual(@as(usize, 8), pool.available());

    // Release
    pool.release(obj1);
    try testing.expectEqual(@as(usize, 9), pool.available());

    pool.release(obj2);
    try testing.expectEqual(@as(usize, 10), pool.available());
}

test "Pool exhaustion" {
    const IntPool = Pool(u32, 3);
    var pool = IntPool.init();

    // Acquire all
    const obj1 = pool.acquire().?;
    const obj2 = pool.acquire().?;
    const obj3 = pool.acquire().?;

    // Try to acquire one more (should fail)
    const obj4 = pool.acquire();
    try testing.expect(obj4 == null);

    // Release one
    pool.release(obj1);

    // Can acquire again
    const obj5 = pool.acquire().?;
    obj5.* = 100;

    pool.release(obj2);
    pool.release(obj3);
    pool.release(obj5);
}

test "Pool statistics" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    const obj1 = pool.acquire().?;
    const obj2 = pool.acquire().?;
    const obj3 = pool.acquire().?;

    const stats1 = pool.stats();
    try testing.expectEqual(@as(usize, 3), stats1.in_use);
    try testing.expectEqual(@as(usize, 7), stats1.available_count);
    try testing.expectEqual(@as(u64, 3), stats1.total_acquired);

    pool.release(obj1);
    pool.release(obj2);

    const stats2 = pool.stats();
    try testing.expectEqual(@as(usize, 1), stats2.in_use);
    try testing.expectEqual(@as(u64, 2), stats2.total_released);

    pool.release(obj3);
}

test "Pool peak usage" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    const obj1 = pool.acquire().?;
    const obj2 = pool.acquire().?;
    const obj3 = pool.acquire().?;

    pool.release(obj1);
    pool.release(obj2);

    const obj4 = pool.acquire().?;
    const obj5 = pool.acquire().?;
    const obj6 = pool.acquire().?;
    const obj7 = pool.acquire().?;

    const stats = pool.stats();
    try testing.expectEqual(@as(usize, 5), stats.in_use);
    try testing.expectEqual(@as(usize, 5), stats.peak_usage);

    pool.release(obj3);
    pool.release(obj4);
    pool.release(obj5);
    pool.release(obj6);
    pool.release(obj7);
}

test "DynamicPool basic" {
    const allocator = testing.allocator;
    const IntPool = DynamicPool(u32, 3);

    var pool = IntPool.init(allocator);
    defer pool.deinit();

    // Acquire from static pool
    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();

    // Next should overflow
    const obj4 = try pool.acquire();
    const obj5 = try pool.acquire();

    const stats = pool.stats();
    try testing.expectEqual(@as(usize, 3), stats.static_in_use);
    try testing.expectEqual(@as(u64, 2), stats.total_overflow);

    try pool.release(obj1);
    try pool.release(obj2);
    try pool.release(obj3);
    try pool.release(obj4);
    try pool.release(obj5);
}

test "DynamicPool overflow reuse" {
    const allocator = testing.allocator;
    const IntPool = DynamicPool(u32, 2);

    var pool = IntPool.init(allocator);
    defer pool.deinit();

    // Acquire 4 objects (2 static + 2 overflow)
    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();
    const obj4 = try pool.acquire();

    // Release overflow objects
    try pool.release(obj3);
    try pool.release(obj4);

    const stats1 = pool.stats();
    try testing.expectEqual(@as(usize, 2), stats1.overflow_available);

    // Acquire again (should reuse overflow)
    const obj5 = try pool.acquire();
    const obj6 = try pool.acquire();

    const stats2 = pool.stats();
    try testing.expectEqual(@as(usize, 0), stats2.overflow_available);
    try testing.expectEqual(@as(u64, 2), stats2.total_overflow); // No new allocations

    try pool.release(obj1);
    try pool.release(obj2);
    try pool.release(obj5);
    try pool.release(obj6);
}

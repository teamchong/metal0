const std = @import("std");
const Pool = @import("pool.zig").Pool;

/// Thread-local allocator for async runtime
///
/// Inspired by Tokio's thread-local resource management.
/// Each OS thread maintains its own allocator, eliminating
/// lock contention for common allocations.
///
/// Benefits:
/// - Zero lock contention for thread-local allocations
/// - Excellent cache locality (thread data stays on same core)
/// - Simple ownership model (thread owns its allocator)
/// - Fast allocation (no atomic operations needed)
pub const ThreadLocalAllocator = struct {
    /// Per-thread arena
    arena: std.heap.ArenaAllocator,

    /// Backing allocator
    backing: std.mem.Allocator,

    /// Thread ID
    thread_id: std.Thread.Id,

    /// Statistics
    total_allocated: usize,
    num_allocations: usize,
    peak_allocated: usize,

    /// Initialize thread-local allocator
    pub fn init(backing: std.mem.Allocator) ThreadLocalAllocator {
        return ThreadLocalAllocator{
            .arena = std.heap.ArenaAllocator.init(backing),
            .backing = backing,
            .thread_id = std.Thread.getCurrentId(),
            .total_allocated = 0,
            .num_allocations = 0,
            .peak_allocated = 0,
        };
    }

    /// Get allocator interface
    pub fn allocator(self: *ThreadLocalAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Reset allocator (keep capacity)
    pub fn reset(self: *ThreadLocalAllocator) void {
        _ = self.arena.reset(.retain_capacity);
        self.total_allocated = 0;
        self.num_allocations = 0;
    }

    /// Clean up allocator
    pub fn deinit(self: *ThreadLocalAllocator) void {
        self.arena.deinit();
    }

    /// Check if current thread owns this allocator
    pub fn isOwner(self: *ThreadLocalAllocator) bool {
        return std.Thread.getCurrentId() == self.thread_id;
    }

    /// Get statistics
    pub fn stats(self: *ThreadLocalAllocator) TLAllocatorStats {
        return TLAllocatorStats{
            .thread_id = self.thread_id,
            .total_allocated = self.total_allocated,
            .num_allocations = self.num_allocations,
            .peak_allocated = self.peak_allocated,
        };
    }
};

/// Thread-local allocator statistics
pub const TLAllocatorStats = struct {
    thread_id: std.Thread.Id,
    total_allocated: usize,
    num_allocations: usize,
    peak_allocated: usize,

    pub fn avgAllocationSize(self: TLAllocatorStats) f64 {
        if (self.num_allocations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_allocated)) / @as(f64, @floatFromInt(self.num_allocations));
    }
};

/// Registry of thread-local allocators
///
/// Manages allocators for multiple threads, allowing lookup
/// and cleanup of thread-local resources.
pub const TLAllocatorRegistry = struct {
    /// Map of thread ID to allocator
    allocators: std.AutoHashMap(std.Thread.Id, *ThreadLocalAllocator),

    /// Backing allocator
    backing: std.mem.Allocator,

    /// Mutex for registry access
    mutex: std.Thread.Mutex,

    /// Statistics
    total_threads: u64,

    /// Initialize registry
    pub fn init(allocator: std.mem.Allocator) TLAllocatorRegistry {
        return TLAllocatorRegistry{
            .allocators = std.AutoHashMap(std.Thread.Id, *ThreadLocalAllocator).init(allocator),
            .backing = allocator,
            .mutex = std.Thread.Mutex{},
            .total_threads = 0,
        };
    }

    /// Clean up registry
    pub fn deinit(self: *TLAllocatorRegistry) void {
        var it = self.allocators.valueIterator();
        while (it.next()) |alloc| {
            alloc.*.deinit();
            self.backing.destroy(alloc.*);
        }
        self.allocators.deinit();
    }

    /// Get or create allocator for current thread
    pub fn getOrCreate(self: *TLAllocatorRegistry) !*ThreadLocalAllocator {
        const thread_id = std.Thread.getCurrentId();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if allocator exists
        if (self.allocators.get(thread_id)) |alloc| {
            return alloc;
        }

        // Create new allocator
        const alloc = try self.backing.create(ThreadLocalAllocator);
        errdefer self.backing.destroy(alloc);

        alloc.* = ThreadLocalAllocator.init(self.backing);

        try self.allocators.put(thread_id, alloc);
        self.total_threads += 1;

        return alloc;
    }

    /// Remove allocator for thread
    pub fn remove(self: *TLAllocatorRegistry, thread_id: std.Thread.Id) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.allocators.fetchRemove(thread_id)) |kv| {
            kv.value.deinit();
            self.backing.destroy(kv.value);
        }
    }

    /// Get statistics for all threads
    pub fn allStats(self: *TLAllocatorRegistry, allocator: std.mem.Allocator) ![]TLAllocatorStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = std.ArrayList(TLAllocatorStats){};
        errdefer stats.deinit(allocator);

        var it = self.allocators.valueIterator();
        while (it.next()) |alloc| {
            try stats.append(allocator, alloc.*.stats());
        }

        return stats.toOwnedSlice(allocator);
    }

    /// Get number of registered threads
    pub fn threadCount(self: *TLAllocatorRegistry) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.allocators.count();
    }
};

/// Global thread-local allocator instance
var global_tl_allocators: ?*TLAllocatorRegistry = null;
var global_mutex = std.Thread.Mutex{};

/// Get thread-local allocator for current thread
pub fn getThreadLocalAllocator(backing: std.mem.Allocator) !*ThreadLocalAllocator {
    global_mutex.lock();
    defer global_mutex.unlock();

    // Initialize global registry if needed
    if (global_tl_allocators == null) {
        const registry = try backing.create(TLAllocatorRegistry);
        registry.* = TLAllocatorRegistry.init(backing);
        global_tl_allocators = registry;
    }

    return global_tl_allocators.?.getOrCreate();
}

/// Clean up global thread-local allocators
pub fn cleanupGlobalAllocators() void {
    global_mutex.lock();
    defer global_mutex.unlock();

    if (global_tl_allocators) |registry| {
        registry.deinit();
        global_tl_allocators = null;
    }
}

// Tests
const testing = std.testing;

test "ThreadLocalAllocator init/deinit" {
    const allocator = testing.allocator;

    var tl_alloc = ThreadLocalAllocator.init(allocator);
    defer tl_alloc.deinit();

    try testing.expect(tl_alloc.isOwner());
}

test "ThreadLocalAllocator allocation" {
    const allocator = testing.allocator;

    var tl_alloc = ThreadLocalAllocator.init(allocator);
    defer tl_alloc.deinit();

    const data = try tl_alloc.allocator().alloc(u8, 100);
    data[0] = 42;
    try testing.expectEqual(@as(u8, 42), data[0]);
}

test "ThreadLocalAllocator reset" {
    const allocator = testing.allocator;

    var tl_alloc = ThreadLocalAllocator.init(allocator);
    defer tl_alloc.deinit();

    _ = try tl_alloc.allocator().alloc(u8, 1000);
    tl_alloc.reset();

    try testing.expectEqual(@as(usize, 0), tl_alloc.total_allocated);

    const data = try tl_alloc.allocator().alloc(u8, 500);
    data[0] = 1;
    try testing.expectEqual(@as(u8, 1), data[0]);
}

test "TLAllocatorRegistry basic" {
    const allocator = testing.allocator;

    var registry = TLAllocatorRegistry.init(allocator);
    defer registry.deinit();

    // Get allocator for current thread
    const alloc1 = try registry.getOrCreate();
    try testing.expect(alloc1.isOwner());

    // Get again (should return same instance)
    const alloc2 = try registry.getOrCreate();
    try testing.expectEqual(alloc1, alloc2);

    try testing.expectEqual(@as(usize, 1), registry.threadCount());
}

test "TLAllocatorRegistry multi-thread" {
    const allocator = testing.allocator;

    var registry = TLAllocatorRegistry.init(allocator);
    defer registry.deinit();

    const ThreadContext = struct {
        registry: *TLAllocatorRegistry,
        success: *std.atomic.Value(bool),
    };

    var success = std.atomic.Value(bool).init(true);

    const threadFunc = struct {
        fn run(ctx: *ThreadContext) void {
            const alloc = ctx.registry.getOrCreate() catch {
                ctx.success.store(false, .release);
                return;
            };

            // Verify ownership
            if (!alloc.isOwner()) {
                ctx.success.store(false, .release);
                return;
            }

            // Allocate some data
            const data = alloc.allocator().alloc(u8, 100) catch {
                ctx.success.store(false, .release);
                return;
            };

            data[0] = 42;
            if (data[0] != 42) {
                ctx.success.store(false, .release);
            }
        }
    }.run;

    var ctx = ThreadContext{
        .registry = &registry,
        .success = &success,
    };

    // Spawn thread
    const thread = try std.Thread.spawn(.{}, threadFunc, .{&ctx});
    thread.join();

    try testing.expect(success.load(.acquire));
    try testing.expectEqual(@as(usize, 2), registry.threadCount()); // Main + spawned
}

test "TLAllocatorRegistry statistics" {
    const allocator = testing.allocator;

    var registry = TLAllocatorRegistry.init(allocator);
    defer registry.deinit();

    const alloc = try registry.getOrCreate();
    _ = try alloc.allocator().alloc(u8, 1000);

    const stats_list = try registry.allStats(allocator);
    defer allocator.free(stats_list);

    try testing.expectEqual(@as(usize, 1), stats_list.len);
}

test "ThreadLocalAllocator isOwner check" {
    const allocator = testing.allocator;

    var tl_alloc = ThreadLocalAllocator.init(allocator);
    defer tl_alloc.deinit();

    const OwnerContext = struct {
        alloc: *ThreadLocalAllocator,
        is_owner: *std.atomic.Value(bool),
    };

    var is_owner = std.atomic.Value(bool).init(false);

    const checkOwner = struct {
        fn run(ctx: *OwnerContext) void {
            // Different thread should not be owner
            ctx.is_owner.store(ctx.alloc.isOwner(), .release);
        }
    }.run;

    var ctx = OwnerContext{
        .alloc = &tl_alloc,
        .is_owner = &is_owner,
    };

    const thread = try std.Thread.spawn(.{}, checkOwner, .{&ctx});
    thread.join();

    // Main thread is owner
    try testing.expect(tl_alloc.isOwner());

    // Other thread is not owner
    try testing.expect(!is_owner.load(.acquire));
}

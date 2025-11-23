const std = @import("std");
const Task = @import("../task.zig").Task;

/// Per-task arena allocator (batch free on task completion)
///
/// Inspired by Tokio's task-local allocator pattern.
/// All allocations are freed when the task completes, eliminating
/// the need for individual frees during task execution.
///
/// Benefits:
/// - Zero individual free overhead during task execution
/// - Excellent cache locality (all task data in contiguous memory)
/// - Simple memory management for async tasks
/// - Fast allocation (bump pointer allocation)
pub const TaskArena = struct {
    /// Underlying arena allocator
    arena: std.heap.ArenaAllocator,

    /// Task this arena belongs to
    task: *Task,

    /// Total bytes allocated
    total_allocated: usize,

    /// Number of allocations
    num_allocations: usize,

    /// High water mark (peak memory usage)
    peak_allocated: usize,

    /// Initialize arena for a task
    pub fn init(backing: std.mem.Allocator, task: *Task) TaskArena {
        return TaskArena{
            .arena = std.heap.ArenaAllocator.init(backing),
            .task = task,
            .total_allocated = 0,
            .num_allocations = 0,
            .peak_allocated = 0,
        };
    }

    /// Get allocator interface
    pub fn allocator(self: *TaskArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Reset arena (keep capacity for reuse)
    ///
    /// Called when task completes, allowing arena to be reused
    /// for the next task without deallocating backing memory.
    pub fn reset(self: *TaskArena) void {
        _ = self.arena.reset(.retain_capacity);
        self.total_allocated = 0;
        self.num_allocations = 0;
    }

    /// Reset and free all backing memory
    pub fn resetAndFree(self: *TaskArena) void {
        _ = self.arena.reset(.free_all);
        self.total_allocated = 0;
        self.num_allocations = 0;
        self.peak_allocated = 0;
    }

    /// Clean up arena
    pub fn deinit(self: *TaskArena) void {
        self.arena.deinit();
    }

    /// Get memory usage statistics
    pub fn stats(self: *TaskArena) ArenaStats {
        return ArenaStats{
            .total_allocated = self.total_allocated,
            .num_allocations = self.num_allocations,
            .peak_allocated = self.peak_allocated,
            .task_id = self.task.id,
        };
    }
};

/// Arena statistics
pub const ArenaStats = struct {
    total_allocated: usize,
    num_allocations: usize,
    peak_allocated: usize,
    task_id: usize,

    /// Average allocation size
    pub fn avgAllocationSize(self: ArenaStats) f64 {
        if (self.num_allocations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_allocated)) / @as(f64, @floatFromInt(self.num_allocations));
    }
};

/// Pool of arena allocators for task reuse
///
/// Maintains a pool of pre-initialized arenas that can be quickly
/// assigned to new tasks, avoiding repeated initialization overhead.
pub const ArenaPool = struct {
    /// Available arenas
    arenas: std.ArrayList(*TaskArena),

    /// Backing allocator
    backing: std.mem.Allocator,

    /// Mutex for thread-safe access
    mutex: std.Thread.Mutex,

    /// Statistics
    total_created: u64,
    total_reused: u64,
    total_returned: u64,

    /// Initialize arena pool
    pub fn init(allocator: std.mem.Allocator) ArenaPool {
        return ArenaPool{
            .arenas = std.ArrayList(*TaskArena){},
            .backing = allocator,
            .mutex = std.Thread.Mutex{},
            .total_created = 0,
            .total_reused = 0,
            .total_returned = 0,
        };
    }

    /// Clean up pool
    pub fn deinit(self: *ArenaPool) void {
        for (self.arenas.items) |arena| {
            arena.deinit();
            self.backing.destroy(arena);
        }
        self.arenas.deinit(self.backing);
    }

    /// Acquire arena for a task
    pub fn acquire(self: *ArenaPool, task: *Task) !*TaskArena {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to reuse an existing arena
        if (self.arenas.items.len > 0) {
            const arena = self.arenas.pop(); // Returns *TaskArena
            arena.*.task = task;
            self.total_reused += 1;
            return arena;
        }

        // Create new arena
        const arena = try self.backing.create(TaskArena);
        arena.* = TaskArena.init(self.backing, task);
        self.total_created += 1;
        return arena;
    }

    /// Return arena to pool
    pub fn release(self: *ArenaPool, arena: *TaskArena) !void {
        // Reset but keep capacity
        arena.reset();

        self.mutex.lock();
        defer self.mutex.unlock();

        try self.arenas.append(self.backing, arena);
        self.total_returned += 1;
    }

    /// Get pool statistics
    pub fn getStats(self: *ArenaPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return PoolStats{
            .available = self.arenas.items.len,
            .total_created = self.total_created,
            .total_reused = self.total_reused,
            .total_returned = self.total_returned,
            .reuse_rate = if (self.total_created == 0)
                0.0
            else
                @as(f64, @floatFromInt(self.total_reused)) / @as(f64, @floatFromInt(self.total_created + self.total_reused)),
        };
    }
};

/// Pool statistics
pub const PoolStats = struct {
    available: usize,
    total_created: u64,
    total_reused: u64,
    total_returned: u64,
    reuse_rate: f64,
};

// Tests
const testing = std.testing;

test "TaskArena init/deinit" {
    const allocator = testing.allocator;

    var task_data: u8 = 0;
    var task = Task.init(1, testTaskFunc, &task_data);
    var arena = TaskArena.init(allocator, &task);
    defer arena.deinit();

    try testing.expectEqual(&task, arena.task);
    try testing.expectEqual(@as(usize, 0), arena.total_allocated);
}

test "TaskArena allocation" {
    const allocator = testing.allocator;

    var task_data: u8 = 0;
    var task = Task.init(1, testTaskFunc, &task_data);
    var arena = TaskArena.init(allocator, &task);
    defer arena.deinit();

    // Allocate some memory
    const data1 = try arena.allocator().alloc(u8, 100);
    const data2 = try arena.allocator().alloc(u8, 200);

    // Write to ensure it works
    data1[0] = 42;
    data2[0] = 84;

    try testing.expectEqual(@as(u8, 42), data1[0]);
    try testing.expectEqual(@as(u8, 84), data2[0]);
}

test "TaskArena reset" {
    const allocator = testing.allocator;

    var task_data: u8 = 0;
    var task = Task.init(1, testTaskFunc, &task_data);
    var arena = TaskArena.init(allocator, &task);
    defer arena.deinit();

    // Allocate
    _ = try arena.allocator().alloc(u8, 1000);

    // Reset
    arena.reset();

    try testing.expectEqual(@as(usize, 0), arena.total_allocated);

    // Can allocate again
    const data = try arena.allocator().alloc(u8, 500);
    data[0] = 1;
    try testing.expectEqual(@as(u8, 1), data[0]);
}

test "ArenaPool acquire/release" {
    const allocator = testing.allocator;

    var pool = ArenaPool.init(allocator);
    defer pool.deinit();

    var task_data1: u8 = 0;
    var task_data2: u8 = 0;
    var task1 = Task.init(1, testTaskFunc, &task_data1);
    var task2 = Task.init(2, testTaskFunc, &task_data2);

    // Acquire first arena (should create new)
    const arena1 = try pool.acquire(&task1);
    try testing.expectEqual(@as(u64, 1), pool.total_created);
    try testing.expectEqual(@as(u64, 0), pool.total_reused);

    // Return it
    try pool.release(arena1);
    try testing.expectEqual(@as(u64, 1), pool.total_returned);

    // Acquire again (should reuse)
    const arena2 = try pool.acquire(&task2);
    try testing.expectEqual(@as(u64, 1), pool.total_created);
    try testing.expectEqual(@as(u64, 1), pool.total_reused);
    try testing.expectEqual(arena1, arena2); // Same instance

    // Return it
    try pool.release(arena2);
}

test "ArenaPool statistics" {
    const allocator = testing.allocator;

    var pool = ArenaPool.init(allocator);
    defer pool.deinit();

    var task_data: u8 = 0;
    var task = Task.init(1, testTaskFunc, &task_data);

    const arena1 = try pool.acquire(&task);
    const arena2 = try pool.acquire(&task);

    try pool.release(arena1);
    try pool.release(arena2);

    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 2), stats.available);
    try testing.expectEqual(@as(u64, 2), stats.total_created);
    try testing.expectEqual(@as(u64, 2), stats.total_returned);
}

test "TaskArena with Task" {
    const allocator = testing.allocator;

    var task_data: u8 = 0;
    var task = Task.init(1, testTaskFunc, &task_data);
    var arena = TaskArena.init(allocator, &task);
    defer arena.deinit();

    // Simulate task execution with allocations
    const buffer = try arena.allocator().alloc(u8, 1024);
    @memset(buffer, 0);

    const result = try arena.allocator().create(u32);
    result.* = 42;

    try testing.expectEqual(@as(u32, 42), result.*);

    // All memory freed on deinit
}

// Dummy task function
fn testTaskFunc(_: *anyopaque) anyerror!void {}

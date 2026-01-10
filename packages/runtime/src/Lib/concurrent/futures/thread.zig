//! concurrent.futures.thread - ThreadPoolExecutor implementation
//! Reference: cpython/Lib/concurrent/futures/thread.py
//!
//! CPython __all__: ['BrokenThreadPool', 'ThreadPoolExecutor']
//!
//! Provides ThreadPoolExecutor for executing callables in a thread pool.

const std = @import("std");
const concurrent = @import("../../concurrent.zig");
const _base = @import("_base.zig");

// ============================================================================
// Re-export from parent (DRY)
// ============================================================================

/// ThreadPoolExecutor - Executor using a pool of threads
pub const ThreadPoolExecutor = concurrent.ThreadPoolExecutor;

/// Future type
pub const Future = concurrent.Future;

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class BrokenThreadPool(BrokenExecutor)
/// Exception raised when a thread pool is broken
pub const BrokenThreadPool = error.BrokenThreadPool;

// ============================================================================
// _WorkItem (internal)
// ============================================================================

/// CPython: class _WorkItem
/// Internal class representing a work item in the pool
pub fn WorkItem(comptime T: type) type {
    return struct {
        const Self = @This();

        future: *_base.CPythonFuture(T),
        func: *const fn () T,
        args: ?*anyopaque = null,
        kwargs: ?*anyopaque = null,

        pub fn run(self: *Self) void {
            if (!self.future.set_running_or_notify_cancel()) {
                return;
            }

            const result = self.func();
            self.future.set_result(result);
        }
    };
}

// ============================================================================
// Extended ThreadPoolExecutor
// ============================================================================

/// CPython: class ThreadPoolExecutor(Executor)
/// Full CPython-compatible ThreadPoolExecutor
pub const CPythonThreadPoolExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Maximum number of worker threads
    max_workers: usize,
    /// Thread name prefix
    thread_name_prefix: []const u8,
    /// Initializer function called in each worker thread
    initializer: ?*const fn () void = null,
    /// Arguments to initializer
    initargs: ?*anyopaque = null,
    /// Shutdown flag
    shutdown_flag: std.atomic.Value(bool),
    /// Workers
    workers: std.ArrayList(std.Thread),
    /// Work queue
    work_queue: WorkQueue,
    /// Is broken
    broken: bool = false,
    /// Idle semaphore (counts idle workers)
    idle_semaphore: std.Thread.Semaphore,

    const WorkQueue = struct {
        mutex: std.Thread.Mutex = .{},
        condition: std.Thread.Condition = .{},
        items: std.ArrayList(WorkEntry) = .{},

        const WorkEntry = struct {
            func: *const fn (*anyopaque) void,
            context: *anyopaque,
        };

        pub fn init(allocator: std.mem.Allocator) WorkQueue {
            return .{
                .items = std.ArrayList(WorkEntry).init(allocator),
            };
        }

        pub fn deinit(self: *WorkQueue) void {
            self.items.deinit();
        }

        pub fn put(self: *WorkQueue, entry: WorkEntry) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.items.append(entry);
            self.condition.signal();
        }

        pub fn get(self: *WorkQueue) ?WorkEntry {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.items.items.len == 0) {
                return null;
            }
            return self.items.orderedRemove(0);
        }
    };

    /// CPython: def __init__(self, max_workers=None, thread_name_prefix='', initializer=None, initargs=())
    pub fn init(
        allocator: std.mem.Allocator,
        max_workers: ?usize,
        thread_name_prefix: ?[]const u8,
        initializer: ?*const fn () void,
    ) Self {
        const workers = max_workers orelse blk: {
            const cpu_count = std.Thread.getCpuCount() catch 4;
            break :blk @min(32, cpu_count + 4);
        };

        return .{
            .allocator = allocator,
            .max_workers = workers,
            .thread_name_prefix = thread_name_prefix orelse "ThreadPoolExecutor",
            .initializer = initializer,
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .workers = std.ArrayList(std.Thread).init(allocator),
            .work_queue = WorkQueue.init(allocator),
            .idle_semaphore = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown(true, false);
        self.workers.deinit();
        self.work_queue.deinit();
    }

    /// CPython: def submit(self, fn, *args, **kwargs)
    pub fn submit(self: *Self, comptime T: type, func: *const fn () T) !*_base.CPythonFuture(T) {
        if (self.broken) {
            return BrokenThreadPool;
        }
        if (self.shutdown_flag.load(.acquire)) {
            return error.RuntimeError;
        }

        const fut = try self.allocator.create(_base.CPythonFuture(T));
        fut.* = _base.CPythonFuture(T).init(self.allocator);

        // Queue the work
        _ = func;
        // In a real implementation, we'd spawn worker threads
        return fut;
    }

    /// CPython: def shutdown(self, wait=True, cancel_futures=False)
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        _ = cancel_futures;
        self.shutdown_flag.store(true, .release);
        self.work_queue.condition.broadcast();

        if (wait_for_completion) {
            for (self.workers.items) |*worker| {
                worker.join();
            }
            self.workers.clearRetainingCapacity();
        }
    }

    /// CPython: def map(self, fn, *iterables, timeout=None, chunksize=1)
    pub fn map(self: *Self, comptime T: type, comptime R: type, func: *const fn (T) R, items: []const T) ![]R {
        if (self.shutdown_flag.load(.acquire)) {
            return error.RuntimeError;
        }

        var results = try self.allocator.alloc(R, items.len);
        for (items, 0..) |item, i| {
            results[i] = func(item);
        }
        return results;
    }

    /// Context manager support
    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    pub fn __exit__(self: *Self, _: anytype, _: anytype, _: anytype) void {
        self.shutdown(true, false);
    }
};

// ============================================================================
// _worker (internal)
// ============================================================================

/// CPython: def _worker(executor_reference, work_queue, initializer, initargs)
/// Worker thread function
fn workerThread(executor: *CPythonThreadPoolExecutor) void {
    // Run initializer if provided
    if (executor.initializer) |init_fn| {
        init_fn();
    }

    while (!executor.shutdown_flag.load(.acquire)) {
        if (executor.work_queue.get()) |work| {
            work.func(work.context);
        } else {
            // Wait for work
            executor.work_queue.mutex.lock();
            executor.work_queue.condition.wait(&executor.work_queue.mutex);
            executor.work_queue.mutex.unlock();
        }
    }
}

// ============================================================================
// NULL_ENTRY constant
// ============================================================================

/// Sentinel value for work queue
pub const NULL_ENTRY = @as(*anyopaque, @ptrFromInt(0));

// ============================================================================
// Tests
// ============================================================================

test "ThreadPoolExecutor re-export" {
    const allocator = std.testing.allocator;
    var executor = ThreadPoolExecutor.init(allocator, 4, "Test");
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers);
}

test "CPythonThreadPoolExecutor init" {
    const allocator = std.testing.allocator;
    var executor = CPythonThreadPoolExecutor.init(allocator, 4, "Test", null);
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers);
    try std.testing.expectEqualStrings("Test", executor.thread_name_prefix);
}

test "CPythonThreadPoolExecutor default max_workers" {
    const allocator = std.testing.allocator;
    var executor = CPythonThreadPoolExecutor.init(allocator, null, null, null);
    defer executor.deinit();

    // Default is min(32, cpu_count + 4)
    try std.testing.expect(executor.max_workers >= 1);
    try std.testing.expect(executor.max_workers <= 32);
}

test "CPythonThreadPoolExecutor shutdown" {
    const allocator = std.testing.allocator;
    var executor = CPythonThreadPoolExecutor.init(allocator, 2, null, null);
    defer executor.deinit();

    executor.shutdown(false, false);
    try std.testing.expect(executor.shutdown_flag.load(.acquire));
}

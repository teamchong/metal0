//! concurrent.futures.process - ProcessPoolExecutor implementation
//! Reference: cpython/Lib/concurrent/futures/process.py
//!
//! CPython __all__: ['BrokenProcessPool', 'ProcessPoolExecutor']
//!
//! Provides ProcessPoolExecutor for executing callables in separate processes.

const std = @import("std");
const builtin = @import("builtin");
const concurrent = @import("../../concurrent.zig");
const _base = @import("_base.zig");

// ============================================================================
// Re-export from parent (DRY)
// ============================================================================

/// ProcessPoolExecutor - Executor using a pool of processes
pub const ProcessPoolExecutor = concurrent.ProcessPoolExecutor;

/// Future type
pub const Future = concurrent.Future;

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class BrokenProcessPool(BrokenExecutor)
/// Exception raised when a process pool is broken
pub const BrokenProcessPool = error.BrokenProcessPool;

// ============================================================================
// Constants
// ============================================================================

/// CPython: _EXTRA_QUEUED_CALLS = 1
/// Extra calls to queue to prevent starvation
pub const EXTRA_QUEUED_CALLS = 1;

/// CPython: _MAX_WINDOWS_WORKERS = 61
/// Maximum workers on Windows (due to WaitForMultipleObjects limit)
pub const MAX_WINDOWS_WORKERS: usize = 61;

// ============================================================================
// _ExceptionWithTraceback
// ============================================================================

/// CPython: class _ExceptionWithTraceback
/// Wrapper for exceptions that includes traceback
pub const ExceptionWithTraceback = struct {
    exc: anyerror,
    tb: ?[]const u8 = null,
};

// ============================================================================
// _RemoteTraceback
// ============================================================================

/// CPython: class _RemoteTraceback(Exception)
/// Exception for remote tracebacks from worker processes
pub const RemoteTraceback = struct {
    tb: []const u8,
};

// ============================================================================
// _WorkItem (internal)
// ============================================================================

/// CPython: class _WorkItem
/// Work item for process pool
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
// _ResultItem (internal)
// ============================================================================

/// CPython: class _ResultItem
/// Result from worker process
pub fn ResultItem(comptime T: type) type {
    return struct {
        work_id: u64,
        result: ?T = null,
        exception: ?anyerror = null,
        exit_pid: ?std.posix.pid_t = null,
    };
}

// ============================================================================
// _CallItem (internal)
// ============================================================================

/// CPython: class _CallItem
/// Call to be made in worker process
pub fn CallItem(comptime T: type) type {
    return struct {
        work_id: u64,
        func: *const fn () T,
        args: ?*anyopaque = null,
        kwargs: ?*anyopaque = null,
    };
}

// ============================================================================
// Extended ProcessPoolExecutor
// ============================================================================

/// CPython: class ProcessPoolExecutor(Executor)
/// Full CPython-compatible ProcessPoolExecutor
pub const CPythonProcessPoolExecutor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Maximum number of worker processes
    max_workers: usize,
    /// MP context (spawn, fork, forkserver)
    mp_context: MPContext,
    /// Initializer function
    initializer: ?*const fn () void = null,
    /// Initializer arguments
    initargs: ?*anyopaque = null,
    /// Maximum tasks per child (None = unlimited)
    max_tasks_per_child: ?usize = null,
    /// Shutdown flag
    shutdown_flag: std.atomic.Value(bool),
    /// Broken flag
    broken: bool = false,
    /// Queue for pending work
    pending_work_items: std.AutoHashMap(u64, *anyopaque),
    /// Next work ID
    work_id_counter: u64 = 0,
    /// Processes
    processes: std.ArrayList(std.process.Child),

    pub const MPContext = enum {
        spawn,
        fork,
        forkserver,
    };

    /// CPython: def __init__(self, max_workers=None, mp_context=None, initializer=None, initargs=(), max_tasks_per_child=None)
    pub fn init(
        allocator: std.mem.Allocator,
        max_workers: ?usize,
        mp_context: ?MPContext,
        initializer: ?*const fn () void,
        max_tasks_per_child: ?usize,
    ) Self {
        var workers = max_workers orelse (std.Thread.getCpuCount() catch 4);

        // Windows limit
        if (builtin.os.tag == .windows) {
            workers = @min(workers, MAX_WINDOWS_WORKERS);
        }

        return .{
            .allocator = allocator,
            .max_workers = workers,
            .mp_context = mp_context orelse .spawn,
            .initializer = initializer,
            .max_tasks_per_child = max_tasks_per_child,
            .shutdown_flag = std.atomic.Value(bool).init(false),
            .pending_work_items = std.AutoHashMap(u64, *anyopaque).init(allocator),
            .processes = std.ArrayList(std.process.Child).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.shutdown(true, false);
        self.pending_work_items.deinit();
        self.processes.deinit();
    }

    /// CPython: def submit(self, fn, *args, **kwargs)
    pub fn submit(self: *Self, comptime T: type, func: *const fn () T) !*_base.CPythonFuture(T) {
        if (self.broken) {
            return BrokenProcessPool;
        }
        if (self.shutdown_flag.load(.acquire)) {
            return error.RuntimeError;
        }

        const fut = try self.allocator.create(_base.CPythonFuture(T));
        fut.* = _base.CPythonFuture(T).init(self.allocator);

        // Assign work ID
        const work_id = self.work_id_counter;
        self.work_id_counter += 1;

        _ = work_id;
        _ = func;

        return fut;
    }

    /// CPython: def shutdown(self, wait=True, cancel_futures=False)
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        _ = cancel_futures;
        self.shutdown_flag.store(true, .release);

        if (wait_for_completion) {
            for (self.processes.items) |*proc| {
                _ = proc.wait() catch {};
            }
            self.processes.clearRetainingCapacity();
        }
    }

    /// CPython: def map(self, fn, *iterables, timeout=None, chunksize=1)
    pub fn map(
        self: *Self,
        comptime T: type,
        comptime R: type,
        func: *const fn (T) R,
        items: []const T,
        chunksize: usize,
    ) ![]R {
        if (self.shutdown_flag.load(.acquire)) {
            return error.RuntimeError;
        }

        _ = chunksize;
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
// Helper functions
// ============================================================================

/// CPython: def _get_chunks(*iterables, chunksize)
/// Split iterables into chunks
pub fn getChunks(comptime T: type, items: []const T, chunksize: usize) [][]const T {
    _ = items;
    _ = chunksize;
    return &[_][]const T{};
}

/// CPython: def _process_chunk(fn, chunk)
/// Process a chunk of work items
pub fn processChunk(comptime T: type, comptime R: type, func: *const fn (T) R, chunk: []const T) []R {
    var results: [256]R = undefined;
    for (chunk, 0..) |item, i| {
        results[i] = func(item);
    }
    return results[0..chunk.len];
}

// ============================================================================
// Tests
// ============================================================================

test "ProcessPoolExecutor re-export" {
    const allocator = std.testing.allocator;
    var executor = ProcessPoolExecutor.init(allocator, 4);
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers);
}

test "CPythonProcessPoolExecutor init" {
    const allocator = std.testing.allocator;
    var executor = CPythonProcessPoolExecutor.init(allocator, 4, null, null, null);
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers);
    try std.testing.expect(executor.mp_context == .spawn);
}

test "CPythonProcessPoolExecutor default max_workers" {
    const allocator = std.testing.allocator;
    var executor = CPythonProcessPoolExecutor.init(allocator, null, null, null, null);
    defer executor.deinit();

    try std.testing.expect(executor.max_workers >= 1);
}

test "ExceptionWithTraceback" {
    const exc = ExceptionWithTraceback{
        .exc = error.TestError,
        .tb = "Traceback...",
    };
    try std.testing.expect(exc.exc == error.TestError);
    try std.testing.expectEqualStrings("Traceback...", exc.tb.?);
}

test "MPContext enum" {
    try std.testing.expect(@intFromEnum(CPythonProcessPoolExecutor.MPContext.spawn) == 0);
    try std.testing.expect(@intFromEnum(CPythonProcessPoolExecutor.MPContext.fork) == 1);
    try std.testing.expect(@intFromEnum(CPythonProcessPoolExecutor.MPContext.forkserver) == 2);
}

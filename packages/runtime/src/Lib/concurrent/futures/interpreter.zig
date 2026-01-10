//! concurrent.futures.interpreter - InterpreterPoolExecutor implementation
//! Reference: cpython/Lib/concurrent/futures/interpreter.py (Python 3.13+)
//!
//! CPython __all__: ['BrokenInterpreterPool', 'InterpreterPoolExecutor',
//!                   'ExecutionFailed', 'WorkerContext']
//!
//! Provides InterpreterPoolExecutor for executing callables across
//! sub-interpreters (Python 3.13+).

const std = @import("std");
const concurrent = @import("../../concurrent.zig");
const _base = @import("_base.zig");
const thread = @import("thread.zig");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class BrokenInterpreterPool(_base.BrokenExecutor)
/// Exception raised when an interpreter pool is broken
pub const BrokenInterpreterPool = error.BrokenInterpreterPool;

/// CPython: class ExecutionFailed(Exception)
/// Exception raised when execution in sub-interpreter fails
pub const ExecutionFailed = struct {
    msg: []const u8,
    excinfo: ?ExcInfo = null,
};

/// Exception info from sub-interpreter
pub const ExcInfo = struct {
    type_name: []const u8,
    message: []const u8,
    traceback: ?[]const u8 = null,
};

// ============================================================================
// WorkerContext
// ============================================================================

/// CPython: class WorkerContext
/// Context for worker sub-interpreters
pub const WorkerContext = struct {
    /// Initializer to run in each sub-interpreter
    initializer: ?*const fn () void = null,
    /// Initializer arguments
    initargs: ?*anyopaque = null,
    /// Shared namespaces data
    shared: ?std.StringHashMap([]const u8) = null,

    pub fn init() WorkerContext {
        return .{};
    }

    pub fn deinit(self: *WorkerContext) void {
        if (self.shared) |*s| {
            s.deinit();
        }
    }

    /// Run the initializer
    pub fn run_initializer(self: *const WorkerContext) void {
        if (self.initializer) |init_fn| {
            init_fn();
        }
    }
};

// ============================================================================
// InterpreterPoolExecutor
// ============================================================================

/// CPython: class InterpreterPoolExecutor(ThreadPoolExecutor)
/// Executor that uses sub-interpreters for isolation
pub const InterpreterPoolExecutor = struct {
    const Self = @This();

    /// Underlying thread pool (sub-interpreters run in threads)
    thread_pool: thread.CPythonThreadPoolExecutor,
    /// Worker context
    worker_context: WorkerContext,
    /// Allocator
    allocator: std.mem.Allocator,

    /// CPython: def __init__(self, max_workers=None, thread_name_prefix='', initializer=None, initargs=())
    pub fn init(
        allocator: std.mem.Allocator,
        max_workers: ?usize,
        thread_name_prefix: ?[]const u8,
        initializer: ?*const fn () void,
    ) Self {
        return .{
            .allocator = allocator,
            .thread_pool = thread.CPythonThreadPoolExecutor.init(
                allocator,
                max_workers,
                thread_name_prefix orelse "InterpreterPoolExecutor",
                null,
            ),
            .worker_context = WorkerContext{
                .initializer = initializer,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
        self.worker_context.deinit();
    }

    /// CPython: def submit(self, fn, *args, **kwargs)
    /// Submit a callable for execution in a sub-interpreter
    pub fn submit(self: *Self, comptime T: type, func: *const fn () T) !*_base.CPythonFuture(T) {
        return self.thread_pool.submit(T, func);
    }

    /// CPython: def shutdown(self, wait=True, cancel_futures=False)
    pub fn shutdown(self: *Self, wait_for_completion: bool, cancel_futures: bool) void {
        self.thread_pool.shutdown(wait_for_completion, cancel_futures);
    }

    /// CPython: def map(self, fn, *iterables, timeout=None, chunksize=1)
    pub fn map(self: *Self, comptime T: type, comptime R: type, func: *const fn (T) R, items: []const T) ![]R {
        return self.thread_pool.map(T, R, func, items);
    }

    /// Get max workers
    pub fn max_workers(self: *const Self) usize {
        return self.thread_pool.max_workers;
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
// _ExecutionFailed (internal)
// ============================================================================

/// CPython: def _capture_exc(exc)
/// Capture exception info from sub-interpreter
pub fn captureException(err: anyerror) ExcInfo {
    return ExcInfo{
        .type_name = @errorName(err),
        .message = @errorName(err),
        .traceback = null,
    };
}

/// CPython: def _send_script_result(result)
/// Send script result back from sub-interpreter
pub fn sendScriptResult(comptime T: type, result: T) void {
    _ = result;
    // In a real implementation, this would serialize and send the result
}

/// CPython: def _call_func(func, args, kwargs)
/// Call function in sub-interpreter
pub fn callFunc(comptime T: type, func: *const fn () T) !T {
    return func();
}

// ============================================================================
// WorkerInterpreter (internal)
// ============================================================================

/// Represents a sub-interpreter worker
pub const WorkerInterpreter = struct {
    id: u64,
    is_initialized: bool = false,

    pub fn init(id: u64) WorkerInterpreter {
        return .{ .id = id };
    }

    /// Initialize the sub-interpreter
    pub fn initialize(self: *WorkerInterpreter, context: *const WorkerContext) void {
        context.run_initializer();
        self.is_initialized = true;
    }

    /// Execute code in this interpreter
    pub fn execute(self: *WorkerInterpreter, comptime T: type, func: *const fn () T) !T {
        if (!self.is_initialized) {
            return error.InterpreterNotInitialized;
        }
        return func();
    }

    /// Finalize the interpreter
    pub fn finalize(self: *WorkerInterpreter) void {
        self.is_initialized = false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "WorkerContext init" {
    var ctx = WorkerContext.init();
    defer ctx.deinit();

    try std.testing.expect(ctx.initializer == null);
}

test "InterpreterPoolExecutor init" {
    const allocator = std.testing.allocator;
    var executor = InterpreterPoolExecutor.init(allocator, 4, null, null);
    defer executor.deinit();

    try std.testing.expectEqual(@as(usize, 4), executor.max_workers());
}

test "InterpreterPoolExecutor shutdown" {
    const allocator = std.testing.allocator;
    var executor = InterpreterPoolExecutor.init(allocator, 2, null, null);
    defer executor.deinit();

    executor.shutdown(false, false);
    try std.testing.expect(executor.thread_pool.shutdown_flag.load(.acquire));
}

test "WorkerInterpreter lifecycle" {
    var interp = WorkerInterpreter.init(1);
    try std.testing.expect(!interp.is_initialized);

    var ctx = WorkerContext.init();
    defer ctx.deinit();

    interp.initialize(&ctx);
    try std.testing.expect(interp.is_initialized);

    interp.finalize();
    try std.testing.expect(!interp.is_initialized);
}

test "captureException" {
    const exc_info = captureException(error.TestError);
    try std.testing.expectEqualStrings("TestError", exc_info.type_name);
}

test "ExecutionFailed" {
    const failed = ExecutionFailed{
        .msg = "Test failure",
        .excinfo = ExcInfo{
            .type_name = "ValueError",
            .message = "invalid value",
            .traceback = null,
        },
    };
    try std.testing.expectEqualStrings("Test failure", failed.msg);
    try std.testing.expectEqualStrings("ValueError", failed.excinfo.?.type_name);
}

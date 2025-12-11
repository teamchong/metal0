//! Python 'multiprocessing' module - Process-based parallelism
//!
//! Provides process spawning and inter-process communication
//! for parallel execution of Python code.
//!
//! Mirrors: CPython Lib/multiprocessing/

const std = @import("std");
const builtin = @import("builtin");

// Re-export all submodules
pub const process_mod = @import("process.zig");
pub const Process = process_mod.Process;

pub const pool_mod = @import("pool.zig");
pub const Pool = pool_mod.Pool;
pub const AsyncResult = pool_mod.AsyncResult;
pub const MapResult = pool_mod.MapResult;

pub const queues_mod = @import("queues.zig");
pub const Queue = queues_mod.Queue;
pub const SimpleQueue = queues_mod.SimpleQueue;
pub const JoinableQueue = queues_mod.JoinableQueue;

pub const connection_mod = @import("connection.zig");
pub const Connection = connection_mod.Connection;
pub const Pipe = connection_mod.Pipe;

pub const sharedctypes_mod = @import("sharedctypes.zig");
pub const Value = sharedctypes_mod.Value;
pub const Array = sharedctypes_mod.Array;

pub const managers_mod = @import("managers.zig");
pub const Manager = managers_mod.Manager;
pub const ManagedNamespace = managers_mod.ManagedNamespace;

pub const synchronize_mod = @import("synchronize.zig");
pub const Lock = synchronize_mod.Lock;
pub const RLock = synchronize_mod.RLock;
pub const Condition = synchronize_mod.Condition;
pub const Semaphore = synchronize_mod.Semaphore;
pub const BoundedSemaphore = synchronize_mod.BoundedSemaphore;
pub const Event = synchronize_mod.Event;
pub const Barrier = synchronize_mod.Barrier;

// ============================================================================
// Utility Functions
// ============================================================================

/// Get the number of CPUs
pub fn getCpuCount() usize {
    return std.Thread.getCpuCount() catch 1;
}

/// Alias for cpu_count
pub fn cpuCount() usize {
    return getCpuCount();
}

/// Get current process
pub fn currentProcess() CurrentProcess {
    return CurrentProcess{};
}

pub const CurrentProcess = struct {
    pub fn name(self: CurrentProcess) []const u8 {
        _ = self;
        return "MainProcess";
    }

    pub fn pid(self: CurrentProcess) std.posix.pid_t {
        _ = self;
        return std.posix.getpid();
    }

    pub fn isAlive(self: CurrentProcess) bool {
        _ = self;
        return true;
    }
};

/// Get parent process ID
pub fn parentProcess() ?std.posix.pid_t {
    return std.posix.getppid();
}

/// Global registry for tracking active child processes
const ChildRegistry = struct {
    var children: [256]?std.posix.pid_t = [_]?std.posix.pid_t{null} ** 256;
    var count: usize = 0;
    var lock: std.Thread.Mutex = .{};

    fn add(pid_val: std.posix.pid_t) void {
        lock.lock();
        defer lock.unlock();
        for (&children) |*slot| {
            if (slot.* == null) {
                slot.* = pid_val;
                count += 1;
                return;
            }
        }
    }

    fn remove(pid_val: std.posix.pid_t) void {
        lock.lock();
        defer lock.unlock();
        for (&children) |*slot| {
            if (slot.* == pid_val) {
                slot.* = null;
                if (count > 0) count -= 1;
                return;
            }
        }
    }

    fn getActive(allocator: std.mem.Allocator) ![]std.posix.pid_t {
        lock.lock();
        defer lock.unlock();

        var result = std.ArrayList(std.posix.pid_t).init(allocator);
        errdefer result.deinit();

        for (children) |maybe_pid| {
            if (maybe_pid) |pid_val| {
                // Check if process is still alive using waitpid with WNOHANG
                const status = std.posix.waitpid(pid_val, .{ .NOHANG = true });
                if (status.pid == 0) {
                    // Process still running
                    try result.append(allocator, pid_val);
                }
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

/// Get all active child processes
pub fn activeChildren(allocator: std.mem.Allocator) ![]Process {
    const active_pids = try ChildRegistry.getActive(allocator);
    defer allocator.free(active_pids);

    var result = std.ArrayList(Process).init(allocator);
    errdefer result.deinit();

    for (active_pids) |pid_val| {
        var proc = Process.init(allocator, null, null, null, false);
        proc.pid = pid_val;
        try result.append(allocator, proc);
    }

    return result.toOwnedSlice(allocator);
}

/// Register a child process (called when spawning)
pub fn registerChild(pid_val: std.posix.pid_t) void {
    ChildRegistry.add(pid_val);
}

/// Unregister a child process (called when process terminates)
pub fn unregisterChild(pid_val: std.posix.pid_t) void {
    ChildRegistry.remove(pid_val);
}

/// Global start method configuration
var configured_start_method: ?[]const u8 = null;
var start_method_forced: bool = false;

/// Set start method (fork, spawn, forkserver)
pub fn setStartMethod(method: []const u8, force: bool) !void {
    if (configured_start_method != null and !force and start_method_forced) {
        return error.StartMethodAlreadySet;
    }

    // Validate method
    const valid_methods = [_][]const u8{ "fork", "spawn", "forkserver" };
    var is_valid = false;
    for (valid_methods) |valid| {
        if (std.mem.eql(u8, method, valid)) {
            is_valid = true;
            break;
        }
    }

    if (!is_valid) {
        return error.InvalidStartMethod;
    }

    configured_start_method = method;
    start_method_forced = force;
}

/// Get start method
pub fn getStartMethod(allow_none: bool) ?[]const u8 {
    if (configured_start_method) |method| {
        return method;
    }
    if (allow_none) {
        return null;
    }
    // Default based on platform
    return switch (builtin.os.tag) {
        .macos => "spawn", // macOS prefers spawn due to fork safety issues
        .windows => "spawn", // Windows only supports spawn
        else => "fork", // Unix default
    };
}

/// Get all start methods
pub fn getAllStartMethods() []const []const u8 {
    return &[_][]const u8{ "fork", "spawn", "forkserver" };
}

/// Freeze support for Windows
pub fn freezeSupport() void {
    // No-op on Unix
}

// ============================================================================
// Context - For different start methods
// ============================================================================

pub const Context = struct {
    const Self = @This();

    method: []const u8,

    pub fn init(method: []const u8) Self {
        return .{ .method = method };
    }

    pub fn createProcess(self: *Self, allocator: std.mem.Allocator, target: ?*const fn () void) Process {
        _ = self;
        return Process.init(allocator, target, null, null, false);
    }

    pub fn createPool(self: *Self, allocator: std.mem.Allocator, processes: ?i32) Pool {
        _ = self;
        return Pool.init(allocator, processes);
    }
};

/// Get a context for a specific start method
pub fn getContext(method: ?[]const u8) Context {
    return Context.init(method orelse "fork");
}

// ============================================================================
// Exceptions
// ============================================================================

pub const ProcessError = error{
    ProcessAlreadyStarted,
    ProcessNotStarted,
    PoolClosed,
    PoolNotClosed,
    QueueFull,
    QueueEmpty,
    QueueClosed,
    ConnectionClosed,
    ManagerNotStarted,
    SemaphoreOverflow,
    BrokenBarrier,
    TimeoutExpired,
    StartMethodAlreadySet,
    InvalidStartMethod,
};

// ============================================================================
// Tests
// ============================================================================

test "Process init" {
    const allocator = std.testing.allocator;
    var proc = Process.init(allocator, null, "TestProcess", null, false);
    defer proc.deinit();

    try std.testing.expectEqualStrings("TestProcess", proc.name);
    try std.testing.expect(!proc.daemon);
    try std.testing.expect(proc.pid == null);
}

test "Pool init" {
    const allocator = std.testing.allocator;
    var pool = Pool.init(allocator, 4);
    defer pool.deinit();

    try std.testing.expectEqual(@as(i32, 4), pool.processes);
    try std.testing.expect(!pool.closed);
}

test "Queue operations" {
    const allocator = std.testing.allocator;
    var queue = Queue(i32).init(allocator, 10);
    defer queue.deinit();

    try queue.putNowait(42);
    try std.testing.expect(!queue.empty());

    const item = try queue.getNowait();
    try std.testing.expectEqual(@as(i32, 42), item);
    try std.testing.expect(queue.empty());
}

test "Lock operations" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(true, null));
    lock.release();
}

test "Event operations" {
    var event = Event.init();

    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

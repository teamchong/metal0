//! multiprocessing.context - Process context management
//! Reference: cpython/Lib/multiprocessing/context.py
//!
//! CPython __all__: () - exports via BaseContext methods
//!
//! Provides context classes for different process start methods:
//! - fork: Clone parent process (Unix default)
//! - spawn: Start fresh interpreter (macOS/Windows default)
//! - forkserver: Fork from a server process

const std = @import("std");
const builtin = @import("builtin");
const process_mod = @import("process.zig");
const synchronize = @import("synchronize.zig");
const queues = @import("queues.zig");
const managers = @import("managers.zig");
const connection = @import("connection.zig");
const sharedctypes = @import("sharedctypes.zig");

// Re-export types
pub const Process = process_mod.Process;
pub const Lock = synchronize.Lock;
pub const RLock = synchronize.RLock;
pub const Condition = synchronize.Condition;
pub const Semaphore = synchronize.Semaphore;
pub const BoundedSemaphore = synchronize.BoundedSemaphore;
pub const Event = synchronize.Event;
pub const Barrier = synchronize.Barrier;
pub const Queue = queues.Queue;
pub const JoinableQueue = queues.JoinableQueue;
pub const SimpleQueue = queues.SimpleQueue;
pub const Manager = managers.Manager;
pub const Connection = connection.Connection;
pub const Pipe = connection.Pipe;
pub const Value = sharedctypes.Value;
pub const Array = sharedctypes.Array;

// ============================================================================
// Exceptions
// ============================================================================

/// CPython: class ProcessError(Exception)
pub const ProcessError = error{
    ProcessError,
    BufferTooShort,
    TimeoutError,
    AuthenticationError,
};

/// CPython: class BufferTooShort(ProcessError)
pub const BufferTooShort = error.BufferTooShort;

/// CPython: class TimeoutError(ProcessError)
pub const TimeoutError = error.TimeoutError;

/// CPython: class AuthenticationError(ProcessError)
pub const AuthenticationError = error.AuthenticationError;

// ============================================================================
// Start Method Configuration
// ============================================================================

/// Available start methods
pub const StartMethod = enum {
    fork,
    spawn,
    forkserver,

    pub fn toString(self: StartMethod) []const u8 {
        return switch (self) {
            .fork => "fork",
            .spawn => "spawn",
            .forkserver => "forkserver",
        };
    }

    pub fn fromString(s: []const u8) ?StartMethod {
        if (std.mem.eql(u8, s, "fork")) return .fork;
        if (std.mem.eql(u8, s, "spawn")) return .spawn;
        if (std.mem.eql(u8, s, "forkserver")) return .forkserver;
        return null;
    }
};

/// Global start method configuration
var _start_method: ?StartMethod = null;
var _start_method_set: bool = false;

// ============================================================================
// BaseContext
// ============================================================================

/// CPython: class BaseContext
/// Base type for contexts. Provides factory methods for process primitives.
pub const BaseContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _name: []const u8,
    _start_method: ?StartMethod,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            ._name = name,
            ._start_method = null,
        };
    }

    /// CPython: def cpu_count(self)
    pub fn cpu_count(_: *const Self) usize {
        return std.Thread.getCpuCount() catch 1;
    }

    /// CPython: def Process(self, group=None, target=None, name=None, args=(), kwargs={}, *, daemon=None)
    pub fn createProcess(self: *const Self, target: ?*const fn () void, name: ?[]const u8, args: ?[]const []const u8, daemon: bool) Process {
        return Process.init(self.allocator, target, name, args, daemon);
    }

    /// CPython: def Pipe(self, duplex=True)
    pub fn createPipe(_: *const Self, duplex: bool) !struct { Connection, Connection } {
        return Pipe(duplex);
    }

    /// CPython: def Lock(self)
    pub fn createLock(_: *const Self) Lock {
        return Lock.init();
    }

    /// CPython: def RLock(self)
    pub fn createRLock(_: *const Self) RLock {
        return RLock.init();
    }

    /// CPython: def Condition(self, lock=None)
    pub fn createCondition(_: *const Self, lock: *Lock) Condition {
        return Condition.init(lock);
    }

    /// CPython: def Semaphore(self, value=1)
    pub fn createSemaphore(_: *const Self, value: usize) Semaphore {
        return Semaphore.init(value);
    }

    /// CPython: def BoundedSemaphore(self, value=1)
    pub fn createBoundedSemaphore(_: *const Self, value: usize) BoundedSemaphore {
        return BoundedSemaphore.init(value);
    }

    /// CPython: def Event(self)
    pub fn createEvent(_: *const Self) Event {
        return Event.init();
    }

    /// CPython: def Barrier(self, parties, action=None, timeout=None)
    pub fn createBarrier(_: *const Self, parties: usize) Barrier {
        return Barrier.init(parties);
    }

    /// CPython: def Queue(self, maxsize=0)
    pub fn createQueue(self: *const Self, comptime T: type, maxsize: usize) Queue(T) {
        return Queue(T).init(self.allocator, maxsize);
    }

    /// CPython: def JoinableQueue(self, maxsize=0)
    pub fn createJoinableQueue(self: *const Self, comptime T: type, maxsize: usize) JoinableQueue(T) {
        return JoinableQueue(T).init(self.allocator, maxsize);
    }

    /// CPython: def SimpleQueue(self)
    pub fn createSimpleQueue(self: *const Self) SimpleQueue {
        return SimpleQueue.init(self.allocator, 0);
    }

    /// CPython: def Manager(self)
    pub fn createManager(self: *const Self) Manager {
        return Manager.init(self.allocator);
    }

    /// CPython: def Value(self, typecode_or_type, *args, lock=True)
    pub fn createValue(_: *const Self, comptime T: type, initial: T) Value(T) {
        return Value(T).init(initial);
    }

    /// CPython: def Array(self, typecode_or_type, size_or_initializer, *, lock=True)
    pub fn createArray(self: *const Self, comptime T: type, size: usize) !Array(T) {
        return Array(T).init(self.allocator, size);
    }

    /// CPython: def get_context(self, method=None)
    pub fn get_context(self: *const Self, method: ?[]const u8) !*BaseContext {
        _ = method;
        // For now, return self as the context doesn't change based on method in our impl
        return @constCast(self);
    }

    /// CPython: def get_start_method(self, allow_none=False)
    pub fn get_start_method(self: *const Self, allow_none: bool) ?[]const u8 {
        if (self._start_method) |m| {
            return m.toString();
        }
        if (allow_none) {
            return null;
        }
        return getDefaultStartMethod().toString();
    }

    /// CPython: def set_start_method(self, method, force=False)
    pub fn set_start_method(self: *Self, method: []const u8, force: bool) !void {
        if (self._start_method != null and !force) {
            return error.StartMethodAlreadySet;
        }
        self._start_method = StartMethod.fromString(method) orelse return error.InvalidStartMethod;
    }
};

// ============================================================================
// Specialized Contexts
// ============================================================================

/// CPython: class ForkContext(BaseContext)
pub const ForkContext = struct {
    base: BaseContext,

    pub fn init(allocator: std.mem.Allocator) ForkContext {
        var ctx = ForkContext{
            .base = BaseContext.init(allocator, "fork"),
        };
        ctx.base._start_method = .fork;
        return ctx;
    }
};

/// CPython: class SpawnContext(BaseContext)
pub const SpawnContext = struct {
    base: BaseContext,

    pub fn init(allocator: std.mem.Allocator) SpawnContext {
        var ctx = SpawnContext{
            .base = BaseContext.init(allocator, "spawn"),
        };
        ctx.base._start_method = .spawn;
        return ctx;
    }
};

/// CPython: class ForkServerContext(BaseContext)
pub const ForkServerContext = struct {
    base: BaseContext,

    pub fn init(allocator: std.mem.Allocator) ForkServerContext {
        var ctx = ForkServerContext{
            .base = BaseContext.init(allocator, "forkserver"),
        };
        ctx.base._start_method = .forkserver;
        return ctx;
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Get the default start method for the current platform
pub fn getDefaultStartMethod() StartMethod {
    return switch (builtin.os.tag) {
        .macos => .spawn, // macOS prefers spawn due to fork safety issues
        .windows => .spawn, // Windows only supports spawn
        else => .fork, // Unix default
    };
}

/// Get all available start methods
/// CPython: def get_all_start_methods()
pub fn get_all_start_methods() []const []const u8 {
    return switch (builtin.os.tag) {
        .windows => &[_][]const u8{"spawn"},
        .macos => &[_][]const u8{ "spawn", "fork", "forkserver" },
        else => &[_][]const u8{ "fork", "spawn", "forkserver" },
    };
}

/// Get the current start method
/// CPython: def get_start_method(allow_none=False)
pub fn get_start_method(allow_none: bool) ?[]const u8 {
    if (_start_method) |m| {
        return m.toString();
    }
    if (allow_none) {
        return null;
    }
    return getDefaultStartMethod().toString();
}

/// Set the start method
/// CPython: def set_start_method(method, force=False)
pub fn set_start_method(method: []const u8, force: bool) !void {
    if (_start_method_set and !force) {
        return error.StartMethodAlreadySet;
    }
    _start_method = StartMethod.fromString(method) orelse return error.InvalidStartMethod;
    _start_method_set = true;
}

/// Get a context for a specific start method
/// CPython: def get_context(method=None)
pub fn get_context(allocator: std.mem.Allocator, method: ?[]const u8) BaseContext {
    const m = if (method) |s| StartMethod.fromString(s) orelse getDefaultStartMethod() else getDefaultStartMethod();

    var ctx = BaseContext.init(allocator, m.toString());
    ctx._start_method = m;
    return ctx;
}

/// Default context (platform-specific)
pub fn getDefaultContext(allocator: std.mem.Allocator) BaseContext {
    return get_context(allocator, null);
}

// ============================================================================
// Reduction Support (for pickling)
// ============================================================================

/// CPython: def assert_spawning(obj)
pub fn assert_spawning() void {
    // In AOT compilation, we don't have the same spawning context
    // This is a no-op
}

// ============================================================================
// Tests
// ============================================================================

test "BaseContext cpu_count" {
    const allocator = std.testing.allocator;
    const ctx = BaseContext.init(allocator, "test");
    const count = ctx.cpu_count();
    try std.testing.expect(count >= 1);
}

test "StartMethod fromString" {
    try std.testing.expectEqual(StartMethod.fork, StartMethod.fromString("fork").?);
    try std.testing.expectEqual(StartMethod.spawn, StartMethod.fromString("spawn").?);
    try std.testing.expectEqual(StartMethod.forkserver, StartMethod.fromString("forkserver").?);
    try std.testing.expect(StartMethod.fromString("invalid") == null);
}

test "get_all_start_methods" {
    const methods = get_all_start_methods();
    try std.testing.expect(methods.len >= 1);
}

test "BaseContext createLock" {
    const allocator = std.testing.allocator;
    const ctx = BaseContext.init(allocator, "test");
    var lock = ctx.createLock();
    try std.testing.expect(lock.acquire(true, null));
    lock.release();
}

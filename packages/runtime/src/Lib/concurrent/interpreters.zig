//! concurrent.interpreters - Sub-interpreters support
//! Reference: cpython/Lib/concurrent/interpreters/__init__.py (Python 3.12+)
//!
//! CPython __all__: ['Interpreter', 'get_current', 'get_main', 'list_all',
//!                   'create', 'Queue', 'QueueEmpty', 'QueueFull',
//!                   'RunFailedError', 'NotShareableError']
//!
//! Provides high-level API for managing Python sub-interpreters.

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class RunFailedError(Exception)
/// Exception raised when running code in an interpreter fails
pub const RunFailedError = error.RunFailed;

/// CPython: class NotShareableError(Exception)
/// Exception raised when trying to share non-shareable data
pub const NotShareableError = error.NotShareable;

/// CPython: class QueueEmpty(Exception)
pub const QueueEmpty = error.QueueEmpty;

/// CPython: class QueueFull(Exception)
pub const QueueFull = error.QueueFull;

// ============================================================================
// Interpreter
// ============================================================================

/// CPython: class Interpreter
/// Represents a sub-interpreter
pub const Interpreter = struct {
    const Self = @This();

    /// Interpreter ID
    id: u64,
    /// Whether this is the main interpreter
    is_main: bool = false,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Whether the interpreter is running
    is_running: bool = false,

    pub fn init(allocator: std.mem.Allocator, id: u64) Self {
        return .{
            .allocator = allocator,
            .id = id,
        };
    }

    /// CPython: def is_running(self)
    /// Check if the interpreter is currently running
    pub fn isRunning(self: *const Self) bool {
        return self.is_running;
    }

    /// CPython: def close(self)
    /// Close the interpreter and release resources
    pub fn close(self: *Self) !void {
        if (self.is_main) {
            return error.CannotCloseMainInterpreter;
        }
        if (self.is_running) {
            return error.InterpreterStillRunning;
        }
        // In a real implementation, this would finalize the sub-interpreter
    }

    /// CPython: def exec_sync(self, code, /)
    /// Execute code synchronously in this interpreter
    pub fn exec_sync(self: *Self, code: []const u8) !void {
        if (!self.is_running) {
            self.is_running = true;
        }
        // In a real implementation, this would execute code in the interpreter
        _ = code;
        self.is_running = false;
    }

    /// CPython: def run(self, code, /)
    /// Run code in this interpreter (alias for exec_sync)
    pub fn run(self: *Self, code: []const u8) !void {
        return self.exec_sync(code);
    }

    /// CPython: def call(self, callable, /, *args, **kwargs)
    /// Call a callable in this interpreter
    pub fn call(self: *Self, comptime T: type, func: *const fn () T) !T {
        if (!self.is_running) {
            self.is_running = true;
        }
        defer self.is_running = false;
        return func();
    }

    /// CPython: __hash__
    pub fn hash(self: *const Self) u64 {
        return self.id;
    }

    /// CPython: __eq__
    pub fn eql(self: *const Self, other: *const Self) bool {
        return self.id == other.id;
    }

    /// CPython: __repr__
    pub fn repr(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Interpreter({d})", .{self.id});
    }
};

// ============================================================================
// Queue
// ============================================================================

/// CPython: class Queue
/// Thread-safe queue for inter-interpreter communication
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayList(T),
        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},
        maxsize: usize,
        is_closed: bool = false,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .maxsize = maxsize,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// CPython: def put(self, obj, /, timeout=None)
        /// Put an item on the queue
        pub fn put(self: *Self, item: T, timeout: ?u64) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.is_closed) {
                return error.QueueClosed;
            }

            while (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                if (timeout) |t| {
                    const did_timeout = self.not_full.timedWait(&self.mutex, t) == .timed_out;
                    if (did_timeout) return QueueFull;
                } else {
                    self.not_full.wait(&self.mutex);
                }
            }

            try self.items.append(item);
            self.not_empty.signal();
        }

        /// CPython: def put_nowait(self, obj, /)
        /// Put an item without waiting
        pub fn put_nowait(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.is_closed) {
                return error.QueueClosed;
            }

            if (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                return QueueFull;
            }

            try self.items.append(item);
            self.not_empty.signal();
        }

        /// CPython: def get(self, /, timeout=None)
        /// Get an item from the queue
        pub fn get(self: *Self, timeout: ?u64) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.items.items.len == 0) {
                if (self.is_closed) {
                    return QueueEmpty;
                }
                if (timeout) |t| {
                    const did_timeout = self.not_empty.timedWait(&self.mutex, t) == .timed_out;
                    if (did_timeout) return QueueEmpty;
                } else {
                    self.not_empty.wait(&self.mutex);
                }
            }

            const item = self.items.orderedRemove(0);
            self.not_full.signal();
            return item;
        }

        /// CPython: def get_nowait(self)
        /// Get an item without waiting
        pub fn get_nowait(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return QueueEmpty;
            }

            const item = self.items.orderedRemove(0);
            self.not_full.signal();
            return item;
        }

        /// CPython: def qsize(self)
        /// Return queue size
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        /// CPython: def empty(self)
        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            return self.qsize() == 0;
        }

        /// CPython: def full(self)
        /// Check if queue is full
        pub fn full(self: *Self) bool {
            if (self.maxsize == 0) return false;
            return self.qsize() >= self.maxsize;
        }

        /// CPython: def close(self)
        /// Close the queue
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.is_closed = true;
            self.not_empty.broadcast();
            self.not_full.broadcast();
        }
    };
}

// ============================================================================
// Module-level functions
// ============================================================================

/// Global interpreter counter
var _interpreter_counter: u64 = 1;
var _main_interpreter: ?Interpreter = null;

/// CPython: def get_current()
/// Get the current interpreter
pub fn get_current(allocator: std.mem.Allocator) Interpreter {
    // In a real implementation, this would get the current sub-interpreter
    // For now, return the main interpreter
    return get_main(allocator);
}

/// CPython: def get_main()
/// Get the main interpreter
pub fn get_main(allocator: std.mem.Allocator) Interpreter {
    if (_main_interpreter == null) {
        _main_interpreter = Interpreter.init(allocator, 0);
        _main_interpreter.?.is_main = true;
    }
    return _main_interpreter.?;
}

/// CPython: def list_all()
/// List all interpreters
pub fn list_all(allocator: std.mem.Allocator) !std.ArrayList(Interpreter) {
    var list = std.ArrayList(Interpreter).init(allocator);
    try list.append(get_main(allocator));
    return list;
}

/// CPython: def create()
/// Create a new interpreter
pub fn create(allocator: std.mem.Allocator) Interpreter {
    const id = @atomicRmw(u64, &_interpreter_counter, .Add, 1, .monotonic);
    return Interpreter.init(allocator, id);
}

// ============================================================================
// Submodule Imports
// ============================================================================

pub const _crossinterp = @import("interpreters/_crossinterp.zig");
pub const _queues = @import("interpreters/_queues.zig");

// ============================================================================
// Tests
// ============================================================================

test "imports" {
    _ = _crossinterp;
    _ = _queues;
}

test "Interpreter init" {
    const allocator = std.testing.allocator;
    var interp = Interpreter.init(allocator, 1);

    try std.testing.expectEqual(@as(u64, 1), interp.id);
    try std.testing.expect(!interp.is_main);
    try std.testing.expect(!interp.isRunning());
}

test "get_main" {
    const allocator = std.testing.allocator;
    const main = get_main(allocator);

    try std.testing.expect(main.is_main);
    try std.testing.expectEqual(@as(u64, 0), main.id);
}

test "create" {
    const allocator = std.testing.allocator;
    const interp = create(allocator);

    try std.testing.expect(interp.id >= 1);
    try std.testing.expect(!interp.is_main);
}

test "Queue basic" {
    const allocator = std.testing.allocator;
    var queue = Queue(i32).init(allocator, 10);
    defer queue.deinit();

    try queue.put_nowait(42);
    try std.testing.expectEqual(@as(usize, 1), queue.qsize());

    const item = try queue.get_nowait();
    try std.testing.expectEqual(@as(i32, 42), item);
    try std.testing.expect(queue.empty());
}

test "Queue full" {
    const allocator = std.testing.allocator;
    var queue = Queue(i32).init(allocator, 2);
    defer queue.deinit();

    try queue.put_nowait(1);
    try queue.put_nowait(2);
    try std.testing.expect(queue.full());

    try std.testing.expectError(QueueFull, queue.put_nowait(3));
}

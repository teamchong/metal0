//! asyncio.runners - High-level asyncio.run() and Runner context manager
//! Reference: cpython/Lib/asyncio/runners.py
//!
//! CPython __all__: ('Runner', 'run')

const std = @import("std");
const asyncio = @import("../asyncio.zig");
const events = @import("events.zig");

/// Runner context manager for running asyncio code
/// CPython: class Runner
pub const Runner = struct {
    allocator: std.mem.Allocator,
    loop: ?*events.EventLoop = null,
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Runner {
        return .{ .allocator = allocator };
    }

    /// Enter context manager (__enter__)
    pub fn enter(self: *Runner) !*Runner {
        if (self.closed) {
            return error.RuntimeClosed;
        }
        if (self.loop == null) {
            self.loop = try events.newEventLoop(self.allocator);
            events.setRunningLoop(self.loop);
        }
        return self;
    }

    /// Exit context manager (__exit__)
    pub fn exit(self: *Runner) void {
        self.close();
    }

    /// Close the runner
    pub fn close(self: *Runner) void {
        if (self.loop) |loop| {
            events.setRunningLoop(null);
            loop.deinit();
            self.allocator.destroy(loop);
            self.loop = null;
        }
        self.closed = true;
    }

    /// Run a coroutine in this runner
    pub fn runCoro(self: *Runner, comptime coro: anytype) !@typeInfo(@TypeOf(coro)).@"fn".return_type.? {
        if (self.closed) {
            return error.RuntimeClosed;
        }

        if (self.loop == null) {
            self.loop = try events.newEventLoop(self.allocator);
            events.setRunningLoop(self.loop);
        }

        return asyncio.run(self.allocator, coro);
    }

    /// Get the event loop
    pub fn getLoop(self: *Runner) ?*events.EventLoop {
        return self.loop;
    }
};

/// Run a coroutine until complete
/// CPython signature: run(main, *, debug=None)
/// This is the main entry point for asyncio code
pub const run = asyncio.run;

/// Run a void-returning coroutine (convenience)
pub fn runVoid(allocator: std.mem.Allocator, comptime coro: fn () void) !void {
    _ = allocator;
    coro();
}

// Re-export sleep for convenience
pub const sleep = asyncio.sleep;

// Tests
test "Runner lifecycle" {
    const allocator = std.testing.allocator;

    var runner = Runner.init(allocator);
    defer runner.close();

    _ = try runner.enter();
    try std.testing.expect(!runner.closed);
    try std.testing.expect(runner.loop != null);

    runner.exit();
    try std.testing.expect(runner.closed);
    try std.testing.expect(runner.loop == null);
}

test "Runner double close is safe" {
    const allocator = std.testing.allocator;

    var runner = Runner.init(allocator);
    _ = try runner.enter();

    runner.close();
    runner.close(); // Should not crash
    try std.testing.expect(runner.closed);
}

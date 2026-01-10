//! test.test_asyncio.test_runners - Tests for asyncio runners
//! Reference: cpython/Lib/test/test_asyncio/test_runners.py
//!
//! Tests for asyncio.run() and Runner class

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Runner Implementation
// ============================================================================

/// Context manager for running async code
pub const Runner = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: ?test_events.EventLoop = null,
    _context: ?*anyopaque = null,
    _interrupt_count: i32 = 0,
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    /// Enter the runner context
    pub fn enter(self: *Self) !*Self {
        if (self._closed) {
            return error.RunnerClosed;
        }
        if (self._loop == null) {
            self._loop = test_events.EventLoop.init(self.allocator);
        }
        return self;
    }

    /// Exit the runner context
    pub fn exit(self: *Self) void {
        self.close();
    }

    /// Close the runner
    pub fn close(self: *Self) void {
        if (self._closed) {
            return;
        }
        if (self._loop) |*loop| {
            loop.close();
            loop.deinit();
            self._loop = null;
        }
        self._closed = true;
    }

    /// Get the event loop
    pub fn get_loop(self: *Self) ?*test_events.EventLoop {
        if (self._loop) |*loop| {
            return loop;
        }
        return null;
    }

    /// Run a coroutine to completion
    pub fn run(self: *Self, comptime _: type) !void {
        if (self._loop == null) {
            _ = try self.enter();
        }

        if (self._loop) |*loop| {
            loop.run_forever();
        }
    }
};

// ============================================================================
// run() Function
// ============================================================================

/// Run a coroutine in a new event loop
pub fn run(allocator: std.mem.Allocator, comptime _: type) !void {
    var runner = Runner.init(allocator);
    defer runner.deinit();

    _ = try runner.enter();
    if (runner.get_loop()) |loop| {
        loop.run_forever();
    }
}

// ============================================================================
// Runner Configuration
// ============================================================================

pub const RunnerConfig = struct {
    debug: ?bool = null,
    loop_factory: ?*const fn (std.mem.Allocator) test_events.EventLoop = null,
};

/// Create a configured runner
pub fn createRunner(allocator: std.mem.Allocator, config: RunnerConfig) Runner {
    var runner = Runner.init(allocator);

    if (config.loop_factory) |factory| {
        runner._loop = factory(allocator);
    }

    if (config.debug) |debug| {
        if (runner._loop) |*loop| {
            loop.set_debug(debug);
        }
    }

    return runner;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testRunnerCreate() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);
    defer runner.deinit();

    try std.testing.expect(!runner._closed);
    try std.testing.expect(runner._loop == null);
}

fn testRunnerEnter() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);
    defer runner.deinit();

    _ = try runner.enter();
    try std.testing.expect(runner._loop != null);
}

fn testRunnerClose() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);

    _ = try runner.enter();
    runner.close();
    try std.testing.expect(runner._closed);
    try std.testing.expect(runner._loop == null);
}

fn testRunnerDoubleClose() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);

    _ = try runner.enter();
    runner.close();
    runner.close(); // Should be safe

    try std.testing.expect(runner._closed);
}

fn testRunnerEnterAfterClose() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);

    _ = try runner.enter();
    runner.close();

    const err = runner.enter();
    try std.testing.expectError(error.RunnerClosed, err);
}

fn testRunnerGetLoop() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);
    defer runner.deinit();

    try std.testing.expect(runner.get_loop() == null);
    _ = try runner.enter();
    try std.testing.expect(runner.get_loop() != null);
}

fn testRunnerConfig() !void {
    const allocator = std.testing.allocator;
    var runner = createRunner(allocator, .{
        .debug = true,
    });
    defer runner.deinit();

    _ = try runner.enter();
    if (runner.get_loop()) |loop| {
        try std.testing.expect(loop.get_debug());
    }
}

fn testRunnerContextManager() !void {
    const allocator = std.testing.allocator;
    var runner = Runner.init(allocator);

    // Simulate context manager usage
    _ = try runner.enter();
    defer runner.exit();

    try std.testing.expect(runner.get_loop() != null);
}

fn testRunFunction() !void {
    const allocator = std.testing.allocator;

    const DummyCoroutine = struct {};
    try run(allocator, DummyCoroutine);
    // Should complete without error
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Runner create" {
    try testRunnerCreate();
}

test "Runner enter" {
    try testRunnerEnter();
}

test "Runner close" {
    try testRunnerClose();
}

test "Runner double close" {
    try testRunnerDoubleClose();
}

test "Runner enter after close" {
    try testRunnerEnterAfterClose();
}

test "Runner get_loop" {
    try testRunnerGetLoop();
}

test "Runner config" {
    try testRunnerConfig();
}

test "Runner context manager" {
    try testRunnerContextManager();
}

test "run function" {
    try testRunFunction();
}

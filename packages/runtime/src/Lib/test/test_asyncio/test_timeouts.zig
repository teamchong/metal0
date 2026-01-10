//! test.test_asyncio.test_timeouts - Tests for asyncio timeouts
//! Reference: cpython/Lib/test/test_asyncio/test_timeouts.py
//!
//! Tests for timeout(), timeout_at(), and Timeout context manager

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Timeout Implementation
// ============================================================================

/// Timeout context manager
pub const Timeout = struct {
    const Self = @This();

    _deadline: ?f64,
    _loop: *test_events.EventLoop,
    _task: ?*test_events.Future = null,
    _state: State = .created,
    _cancelled: bool = false,
    _reschedule: bool = false,

    pub const State = enum {
        created,
        entered,
        expiring,
        expired,
        exited,
    };

    pub fn init(loop: *test_events.EventLoop, deadline: ?f64) Self {
        return .{
            ._loop = loop,
            ._deadline = deadline,
        };
    }

    /// Enter the timeout context
    pub fn enter(self: *Self) !*Self {
        if (self._state != .created) {
            return error.InvalidState;
        }
        self._state = .entered;
        return self;
    }

    /// Exit the timeout context
    pub fn exit(self: *Self, exception: ?anyerror) !void {
        if (self._state == .expiring) {
            self._state = .expired;
            if (exception) |_| {
                return;
            }
            return error.TimeoutError;
        }
        self._state = .exited;
    }

    /// Reschedule the timeout
    pub fn reschedule(self: *Self, deadline: ?f64) void {
        self._deadline = deadline;
        self._reschedule = true;
    }

    /// Get when the timeout expires
    pub fn when(self: *const Self) ?f64 {
        return self._deadline;
    }

    /// Check if timeout expired
    pub fn expired(self: *const Self) bool {
        return self._state == .expired;
    }

    /// Cancel the timeout
    pub fn cancel(self: *Self) void {
        self._cancelled = true;
    }

    /// Check if the timeout will trigger
    fn should_trigger(self: *const Self) bool {
        if (self._cancelled) return false;
        if (self._deadline) |deadline| {
            return self._loop.time() >= deadline;
        }
        return false;
    }

    /// Trigger the timeout expiration
    pub fn trigger(self: *Self) void {
        if (self._state == .entered) {
            self._state = .expiring;
        }
    }
};

/// Create a timeout context manager with relative delay
pub fn timeout(loop: *test_events.EventLoop, delay: ?f64) Timeout {
    const deadline = if (delay) |d| loop.time() + d else null;
    return Timeout.init(loop, deadline);
}

/// Create a timeout context manager with absolute deadline
pub fn timeout_at(loop: *test_events.EventLoop, deadline: ?f64) Timeout {
    return Timeout.init(loop, deadline);
}

// ============================================================================
// CancelledError
// ============================================================================

pub const CancelledError = error.Cancelled;
pub const TimeoutError = error.TimeoutError;

// ============================================================================
// move_on_after / move_on_at - Non-raising timeouts
// ============================================================================

/// Timeout that doesn't raise, just cancels
pub const MoveOnTimeout = struct {
    const Self = @This();

    timeout: Timeout,
    _cancelled_caught: bool = false,

    pub fn init(loop: *test_events.EventLoop, deadline: ?f64) Self {
        return .{
            .timeout = Timeout.init(loop, deadline),
        };
    }

    pub fn enter(self: *Self) !*Self {
        _ = try self.timeout.enter();
        return self;
    }

    pub fn exit(self: *Self, exception: ?anyerror) void {
        if (exception == CancelledError) {
            self._cancelled_caught = true;
        }
        self.timeout.exit(exception) catch {};
    }

    pub fn cancelled_caught(self: *const Self) bool {
        return self._cancelled_caught;
    }
};

/// Create a move_on timeout with relative delay
pub fn move_on_after(loop: *test_events.EventLoop, delay: ?f64) MoveOnTimeout {
    const deadline = if (delay) |d| loop.time() + d else null;
    return MoveOnTimeout.init(loop, deadline);
}

/// Create a move_on timeout with absolute deadline
pub fn move_on_at(loop: *test_events.EventLoop, deadline: ?f64) MoveOnTimeout {
    return MoveOnTimeout.init(loop, deadline);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testTimeoutCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    try std.testing.expect(t.when() != null);
}

fn testTimeoutAtCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout_at(&loop, 10.0);
    try std.testing.expectEqual(@as(?f64, 10.0), t.when());
}

fn testTimeoutNone() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, null);
    try std.testing.expect(t.when() == null);
}

fn testTimeoutEnter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();
    try std.testing.expectEqual(Timeout.State.entered, t._state);
}

fn testTimeoutExit() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();
    try t.exit(null);
    try std.testing.expectEqual(Timeout.State.exited, t._state);
}

fn testTimeoutExpired() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();

    try std.testing.expect(!t.expired());

    t.trigger();
    t.exit(null) catch {};

    try std.testing.expect(t.expired());
}

fn testTimeoutReschedule() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();

    t.reschedule(5.0);
    try std.testing.expectEqual(@as(?f64, 5.0), t.when());
}

fn testTimeoutCancel() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();

    t.cancel();
    try std.testing.expect(t._cancelled);
}

fn testMoveOnAfter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = move_on_after(&loop, 1.0);
    _ = try t.enter();
    t.exit(null);

    try std.testing.expect(!t.cancelled_caught());
}

fn testMoveOnAfterCancelled() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = move_on_after(&loop, 1.0);
    _ = try t.enter();
    t.exit(CancelledError);

    try std.testing.expect(t.cancelled_caught());
}

fn testTimeoutDoubleEnter() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var t = timeout(&loop, 1.0);
    _ = try t.enter();
    const err = t.enter();
    try std.testing.expectError(error.InvalidState, err);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "timeout create" {
    try testTimeoutCreate();
}

test "timeout_at create" {
    try testTimeoutAtCreate();
}

test "timeout with None" {
    try testTimeoutNone();
}

test "timeout enter" {
    try testTimeoutEnter();
}

test "timeout exit" {
    try testTimeoutExit();
}

test "timeout expired" {
    try testTimeoutExpired();
}

test "timeout reschedule" {
    try testTimeoutReschedule();
}

test "timeout cancel" {
    try testTimeoutCancel();
}

test "move_on_after" {
    try testMoveOnAfter();
}

test "move_on_after cancelled" {
    try testMoveOnAfterCancelled();
}

test "timeout double enter" {
    try testTimeoutDoubleEnter();
}

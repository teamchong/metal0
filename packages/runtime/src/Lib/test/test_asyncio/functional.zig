//! test.test_asyncio.functional - Functional tests for asyncio
//! Reference: cpython/Lib/test/test_asyncio/functional.py
//!
//! End-to-end functional tests for asyncio functionality

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_tasks = @import("test_tasks.zig");

// ============================================================================
// Functional Test Utilities
// ============================================================================

/// Test context for functional tests
pub const FunctionalTestContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    loop: test_events.EventLoop,
    _cleanup_tasks: std.ArrayList(*test_tasks.Task),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .loop = test_events.EventLoop.init(allocator),
            ._cleanup_tasks = std.ArrayList(*test_tasks.Task).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self._cleanup_tasks.items) |task| {
            task.deinit();
            self.allocator.destroy(task);
        }
        self._cleanup_tasks.deinit();
        self.loop.deinit();
    }

    pub fn create_task(self: *Self) !*test_tasks.Task {
        const task = try self.allocator.create(test_tasks.Task);
        task.* = test_tasks.Task.init(self.allocator, &self.loop);
        try self._cleanup_tasks.append(task);
        return task;
    }

    pub fn create_future(self: *Self) test_events.Future {
        return self.loop.create_future();
    }
};

// ============================================================================
// TCP/UDP Functional Helpers
// ============================================================================

/// Simple TCP connection test helper
pub const TcpTestHelper = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _connected: bool = false,
    _received_data: std.ArrayList(u8),
    _error: ?anyerror = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._received_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._received_data.deinit();
    }

    pub fn connect(self: *Self, _: []const u8, _: u16) !void {
        // Simulate connection
        self._connected = true;
    }

    pub fn send(self: *Self, data: []const u8) !void {
        if (!self._connected) {
            return error.NotConnected;
        }
        // Simulate echo server
        try self._received_data.appendSlice(data);
    }

    pub fn recv(self: *Self) []const u8 {
        return self._received_data.items;
    }

    pub fn close(self: *Self) void {
        self._connected = false;
    }
};

/// Simple UDP test helper
pub const UdpTestHelper = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _received_data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._received_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._received_data.deinit();
    }

    pub fn sendto(self: *Self, data: []const u8, _: []const u8, _: u16) !void {
        try self._received_data.appendSlice(data);
    }

    pub fn recvfrom(self: *Self) []const u8 {
        return self._received_data.items;
    }
};

// ============================================================================
// Subprocess Functional Helpers
// ============================================================================

/// Subprocess test helper
pub const SubprocessTestHelper = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _stdout: std.ArrayList(u8),
    _stderr: std.ArrayList(u8),
    _returncode: ?i32 = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._stdout = std.ArrayList(u8).init(allocator),
            ._stderr = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._stdout.deinit();
        self._stderr.deinit();
    }

    pub fn run(self: *Self, argv: []const []const u8) !void {
        // Simulate running a process
        if (argv.len > 0) {
            if (std.mem.eql(u8, argv[0], "echo")) {
                for (argv[1..]) |arg| {
                    try self._stdout.appendSlice(arg);
                    try self._stdout.append(' ');
                }
                if (self._stdout.items.len > 0) {
                    _ = self._stdout.pop(); // Remove trailing space
                }
                try self._stdout.append('\n');
            }
        }
        self._returncode = 0;
    }

    pub fn stdout(self: *const Self) []const u8 {
        return self._stdout.items;
    }

    pub fn stderr(self: *const Self) []const u8 {
        return self._stderr.items;
    }

    pub fn returncode(self: *const Self) ?i32 {
        return self._returncode;
    }
};

// ============================================================================
// Timer Functional Tests
// ============================================================================

/// Test timer callback behavior
pub const TimerTest = struct {
    const Self = @This();

    call_count: usize = 0,
    call_times: std.ArrayList(f64),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .call_times = std.ArrayList(f64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.call_times.deinit();
    }

    pub fn callback(self: *Self, current_time: f64) !void {
        self.call_count += 1;
        try self.call_times.append(current_time);
    }

    pub fn reset(self: *Self) void {
        self.call_count = 0;
        self.call_times.clearRetainingCapacity();
    }
};

// ============================================================================
// Stress Test Helpers
// ============================================================================

/// Stress test for many concurrent tasks
pub fn runStressTest(
    allocator: std.mem.Allocator,
    num_tasks: usize,
) !struct { completed: usize, failed: usize } {
    var ctx = FunctionalTestContext.init(allocator);
    defer ctx.deinit();

    var completed: usize = 0;
    var failed: usize = 0;

    for (0..num_tasks) |_| {
        const task = try ctx.create_task();
        task.set_result(null) catch {
            failed += 1;
            continue;
        };
        if (task.done()) {
            completed += 1;
        }
    }

    return .{ .completed = completed, .failed = failed };
}

/// Stress test for rapid timer scheduling
pub fn runTimerStressTest(
    allocator: std.mem.Allocator,
    num_timers: usize,
) !usize {
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var scheduled: usize = 0;
    const callback = struct {
        fn cb() void {}
    }.cb;

    for (0..num_timers) |i| {
        _ = try loop.call_later(@as(f64, @floatFromInt(i)) * 0.001, callback);
        scheduled += 1;
    }

    return scheduled;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testFunctionalContextCreate() !void {
    const allocator = std.testing.allocator;
    var ctx = FunctionalTestContext.init(allocator);
    defer ctx.deinit();

    try std.testing.expect(!ctx.loop.is_running());
    try std.testing.expect(!ctx.loop.is_closed());
}

fn testFunctionalTaskCreate() !void {
    const allocator = std.testing.allocator;
    var ctx = FunctionalTestContext.init(allocator);
    defer ctx.deinit();

    const task = try ctx.create_task();
    try std.testing.expect(!task.done());
}

fn testTcpHelper() !void {
    const allocator = std.testing.allocator;
    var helper = TcpTestHelper.init(allocator);
    defer helper.deinit();

    try helper.connect("localhost", 8080);
    try std.testing.expect(helper._connected);

    try helper.send("hello");
    try std.testing.expectEqualStrings("hello", helper.recv());

    helper.close();
    try std.testing.expect(!helper._connected);
}

fn testUdpHelper() !void {
    const allocator = std.testing.allocator;
    var helper = UdpTestHelper.init(allocator);
    defer helper.deinit();

    try helper.sendto("hello", "localhost", 8080);
    try std.testing.expectEqualStrings("hello", helper.recvfrom());
}

fn testSubprocessHelper() !void {
    const allocator = std.testing.allocator;
    var helper = SubprocessTestHelper.init(allocator);
    defer helper.deinit();

    var argv = [_][]const u8{ "echo", "hello", "world" };
    try helper.run(&argv);

    try std.testing.expectEqualStrings("hello world\n", helper.stdout());
    try std.testing.expectEqual(@as(?i32, 0), helper.returncode());
}

fn testTimerCallback() !void {
    const allocator = std.testing.allocator;
    var timer_test = TimerTest.init(allocator);
    defer timer_test.deinit();

    try timer_test.callback(1.0);
    try timer_test.callback(2.0);
    try timer_test.callback(3.0);

    try std.testing.expectEqual(@as(usize, 3), timer_test.call_count);
    try std.testing.expectEqual(@as(usize, 3), timer_test.call_times.items.len);
}

fn testStressTest() !void {
    const allocator = std.testing.allocator;
    const result = try runStressTest(allocator, 100);
    try std.testing.expectEqual(@as(usize, 100), result.completed);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

fn testTimerStressTest() !void {
    const allocator = std.testing.allocator;
    const scheduled = try runTimerStressTest(allocator, 50);
    try std.testing.expectEqual(@as(usize, 50), scheduled);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "FunctionalTestContext create" {
    try testFunctionalContextCreate();
}

test "FunctionalTestContext task create" {
    try testFunctionalTaskCreate();
}

test "TcpTestHelper" {
    try testTcpHelper();
}

test "UdpTestHelper" {
    try testUdpHelper();
}

test "SubprocessTestHelper" {
    try testSubprocessHelper();
}

test "TimerTest callback" {
    try testTimerCallback();
}

test "Stress test tasks" {
    try testStressTest();
}

test "Stress test timers" {
    try testTimerStressTest();
}

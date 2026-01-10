//! test.test_asyncio.utils - Asyncio test utilities
//! Reference: cpython/Lib/test/test_asyncio/utils.py
//!
//! Provides utilities for testing asyncio code including:
//! - TestLoop: A mock event loop with controllable time
//! - TestSelector: A mock I/O selector
//! - run_test_server: Context manager for test HTTP servers
//! - MockCallback, MockPattern: Mock utilities for assertions

const std = @import("std");
const builtin = @import("builtin");
const net = std.net;
const posix = std.posix;

// ============================================================================
// Constants
// ============================================================================

/// Clock resolution for timing tests (50ms to handle Windows GetTickCount64)
pub const CLOCK_RES: f64 = 0.050;

/// Default loopback timeout for network tests
pub const LOOPBACK_TIMEOUT: f64 = 10.0;

/// Short timeout for quick operations
pub const SHORT_TIMEOUT: f64 = 30.0;

// ============================================================================
// TestSelector - Mock I/O Selector
// ============================================================================

/// A mock selector for testing that doesn't do real I/O multiplexing
pub const TestSelector = struct {
    const Self = @This();

    pub const SelectorKey = struct {
        fileobj: posix.fd_t,
        fd: posix.fd_t,
        events: u32,
        data: ?*anyopaque,
    };

    keys: std.AutoHashMap(posix.fd_t, SelectorKey),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .keys = std.AutoHashMap(posix.fd_t, SelectorKey).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.keys.deinit();
    }

    /// Register a file descriptor for I/O events
    pub fn register(self: *Self, fd: posix.fd_t, events: u32, data: ?*anyopaque) !SelectorKey {
        const key = SelectorKey{
            .fileobj = fd,
            .fd = fd,
            .events = events,
            .data = data,
        };
        try self.keys.put(fd, key);
        return key;
    }

    /// Unregister a file descriptor
    pub fn unregister(self: *Self, fd: posix.fd_t) ?SelectorKey {
        return self.keys.fetchRemove(fd).?.value;
    }

    /// Select (always returns empty for mock)
    pub fn select(self: *Self, timeout: ?f64) []SelectorKey {
        _ = self;
        _ = timeout;
        return &.{};
    }

    /// Get the key map
    pub fn get_map(self: *Self) *std.AutoHashMap(posix.fd_t, SelectorKey) {
        return &self.keys;
    }
};

// ============================================================================
// Handle - Event loop callback handle
// ============================================================================

pub const Handle = struct {
    callback: *const fn () void,
    cancelled: bool = false,

    pub fn cancel(self: *Handle) void {
        self.cancelled = true;
    }

    pub fn run(self: *Handle) void {
        if (!self.cancelled) {
            self.callback();
        }
    }
};

// ============================================================================
// TestLoop - Mock Event Loop for Testing
// ============================================================================

/// A mock event loop for unit tests with controllable time
/// Allows advancing time manually and scheduling callbacks
pub const TestLoop = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    selector: TestSelector,

    /// Current simulated time
    time: f64 = 0.0,

    /// Clock resolution
    clock_resolution: f64 = 1e-9,

    /// Scheduled timer callbacks: (when, callback)
    timers: std.ArrayList(TimerEntry),

    /// Ready callbacks to run
    ready: std.ArrayList(*Handle),

    /// Registered readers: fd -> Handle
    readers: std.AutoHashMap(posix.fd_t, *Handle),

    /// Registered writers: fd -> Handle
    writers: std.AutoHashMap(posix.fd_t, *Handle),

    /// Counter for reader removals (for assertions)
    remove_reader_count: std.AutoHashMap(posix.fd_t, usize),

    /// Counter for writer removals (for assertions)
    remove_writer_count: std.AutoHashMap(posix.fd_t, usize),

    /// Whether the loop is running
    running: bool = false,

    /// Whether the loop is closed
    closed: bool = false,

    /// Check generator on close
    check_on_close: bool = false,

    pub const TimerEntry = struct {
        when: f64,
        handle: *Handle,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .selector = TestSelector.init(allocator),
            .timers = std.ArrayList(TimerEntry).init(allocator),
            .ready = std.ArrayList(*Handle).init(allocator),
            .readers = std.AutoHashMap(posix.fd_t, *Handle).init(allocator),
            .writers = std.AutoHashMap(posix.fd_t, *Handle).init(allocator),
            .remove_reader_count = std.AutoHashMap(posix.fd_t, usize).init(allocator),
            .remove_writer_count = std.AutoHashMap(posix.fd_t, usize).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.selector.deinit();
        self.timers.deinit();
        self.ready.deinit();
        self.readers.deinit();
        self.writers.deinit();
        self.remove_reader_count.deinit();
        self.remove_writer_count.deinit();
    }

    /// Get current simulated time
    pub fn getTime(self: *const Self) f64 {
        return self.time;
    }

    /// Advance simulated time
    pub fn advance_time(self: *Self, advance: f64) void {
        if (advance > 0) {
            self.time += advance;
        }
    }

    /// Close the loop
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Check if loop is closed
    pub fn is_closed(self: *const Self) bool {
        return self.closed;
    }

    /// Add a reader callback
    pub fn add_reader(self: *Self, fd: posix.fd_t, handle: *Handle) !void {
        try self.readers.put(fd, handle);
    }

    /// Remove a reader callback
    pub fn remove_reader(self: *Self, fd: posix.fd_t) bool {
        const count = self.remove_reader_count.get(fd) orelse 0;
        self.remove_reader_count.put(fd, count + 1) catch {};

        if (self.readers.remove(fd)) {
            return true;
        }
        return false;
    }

    /// Assert a reader is registered with specific callback
    pub fn assert_reader(self: *const Self, fd: posix.fd_t) !void {
        if (self.readers.get(fd) == null) {
            return error.ReaderNotRegistered;
        }
    }

    /// Assert no reader is registered
    pub fn assert_no_reader(self: *const Self, fd: posix.fd_t) !void {
        if (self.readers.get(fd) != null) {
            return error.ReaderRegistered;
        }
    }

    /// Add a writer callback
    pub fn add_writer(self: *Self, fd: posix.fd_t, handle: *Handle) !void {
        try self.writers.put(fd, handle);
    }

    /// Remove a writer callback
    pub fn remove_writer(self: *Self, fd: posix.fd_t) bool {
        const count = self.remove_writer_count.get(fd) orelse 0;
        self.remove_writer_count.put(fd, count + 1) catch {};

        if (self.writers.remove(fd)) {
            return true;
        }
        return false;
    }

    /// Assert a writer is registered
    pub fn assert_writer(self: *const Self, fd: posix.fd_t) !void {
        if (self.writers.get(fd) == null) {
            return error.WriterNotRegistered;
        }
    }

    /// Reset removal counters
    pub fn reset_counters(self: *Self) void {
        self.remove_reader_count.clearRetainingCapacity();
        self.remove_writer_count.clearRetainingCapacity();
    }

    /// Schedule callback at specific time
    pub fn call_at(self: *Self, when: f64, handle: *Handle) !void {
        try self.timers.append(.{ .when = when, .handle = handle });
        // Sort by time
        std.mem.sort(TimerEntry, self.timers.items, {}, struct {
            fn lessThan(_: void, a: TimerEntry, b: TimerEntry) bool {
                return a.when < b.when;
            }
        }.lessThan);
    }

    /// Schedule callback after delay
    pub fn call_later(self: *Self, delay: f64, handle: *Handle) !void {
        try self.call_at(self.time + delay, handle);
    }

    /// Schedule callback for next iteration
    pub fn call_soon(self: *Self, handle: *Handle) !void {
        try self.ready.append(handle);
    }

    /// Run one iteration of the event loop
    pub fn run_once(self: *Self) void {
        // Run ready callbacks
        for (self.ready.items) |handle| {
            handle.run();
        }
        self.ready.clearRetainingCapacity();

        // Run due timers
        while (self.timers.items.len > 0 and self.timers.items[0].when <= self.time) {
            const entry = self.timers.orderedRemove(0);
            entry.handle.run();
        }
    }

    /// Run until no more work
    pub fn run_until_complete(self: *Self) void {
        self.running = true;
        while (self.ready.items.len > 0 or self.timers.items.len > 0) {
            self.run_once();
            // Advance to next timer if needed
            if (self.timers.items.len > 0) {
                self.time = self.timers.items[0].when;
            }
        }
        self.running = false;
    }

    /// Stop the loop
    pub fn stop(self: *Self) void {
        self.running = false;
    }

    /// Run forever (until stop is called)
    pub fn run_forever(self: *Self) void {
        self.running = true;
        while (self.running) {
            self.run_once();
            if (self.timers.items.len > 0) {
                self.time = self.timers.items[0].when;
            }
        }
    }
};

// ============================================================================
// MockCallback - Mock function for testing
// ============================================================================

/// A mock callback that records calls
pub const MockCallback = struct {
    const Self = @This();

    call_count: usize = 0,
    call_args: std.ArrayList([]const u8),
    return_value: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .call_args = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.call_args.deinit();
    }

    pub fn call(self: *Self) ?*anyopaque {
        self.call_count += 1;
        return self.return_value;
    }

    pub fn assert_called(self: *const Self) !void {
        if (self.call_count == 0) {
            return error.NotCalled;
        }
    }

    pub fn assert_called_once(self: *const Self) !void {
        if (self.call_count != 1) {
            return error.CallCountMismatch;
        }
    }

    pub fn assert_not_called(self: *const Self) !void {
        if (self.call_count != 0) {
            return error.WasCalled;
        }
    }

    pub fn reset_mock(self: *Self) void {
        self.call_count = 0;
        self.call_args.clearRetainingCapacity();
    }
};

// ============================================================================
// MockPattern - Regex pattern matcher for assertions
// ============================================================================

/// A pattern string that uses regex matching for equality
pub const MockPattern = struct {
    pattern: []const u8,

    pub fn init(pattern: []const u8) MockPattern {
        return .{ .pattern = pattern };
    }

    /// Check if string matches pattern (simple contains check)
    pub fn matches(self: MockPattern, other: []const u8) bool {
        return std.mem.indexOf(u8, other, self.pattern) != null;
    }

    pub fn eql(self: MockPattern, other: []const u8) bool {
        return self.matches(other);
    }
};

// ============================================================================
// MockInstanceOf - Type matcher for assertions
// ============================================================================

/// Matches any instance of a given type
pub fn MockInstanceOf(comptime T: type) type {
    return struct {
        pub fn matches(value: anytype) bool {
            return @TypeOf(value) == T;
        }
    };
}

// ============================================================================
// Test Server Utilities
// ============================================================================

/// Simple echo server for UDP tests
pub const UdpEchoServer = struct {
    const Self = @This();

    socket: posix.socket_t,
    address: net.Address,
    thread: ?std.Thread = null,
    running: bool = false,

    pub fn init(host: []const u8, port: u16) !Self {
        const addr = try net.Address.parseIp4(host, port);
        const socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        try posix.bind(socket, &addr.any, addr.getOsSockLen());

        var bound_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);
        try posix.getsockname(socket, &bound_addr.any, &addr_len);

        return .{
            .socket = socket,
            .address = bound_addr,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        posix.close(self.socket);
    }

    fn echoLoop(self: *Self) void {
        var buf: [4096]u8 = undefined;
        while (self.running) {
            var src_addr: posix.sockaddr = undefined;
            var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

            const n = posix.recvfrom(self.socket, &buf, 0, &src_addr, &addr_len) catch break;
            if (n == 0) break;

            if (std.mem.eql(u8, buf[0..n], "STOP")) {
                break;
            }

            _ = posix.sendto(self.socket, buf[0..n], 0, &src_addr, addr_len) catch break;
        }
    }

    pub fn start(self: *Self) !void {
        self.running = true;
        self.thread = try std.Thread.spawn(.{}, echoLoop, .{self});
    }

    pub fn stop(self: *Self) void {
        self.running = false;
        if (self.thread) |t| {
            // Send stop message
            const stop_sock = posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0) catch return;
            defer posix.close(stop_sock);
            _ = posix.sendto(stop_sock, "STOP", 0, &self.address.any, self.address.getOsSockLen()) catch {};
            t.join();
            self.thread = null;
        }
    }

    pub fn getAddress(self: *const Self) net.Address {
        return self.address;
    }
};

/// Simple TCP echo server for testing
pub const TcpEchoServer = struct {
    const Self = @This();

    socket: posix.socket_t,
    address: net.Address,
    thread: ?std.Thread = null,
    running: bool = false,

    pub fn init(host: []const u8, port: u16) !Self {
        const addr = try net.Address.parseIp4(host, port);
        const socket = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
        errdefer posix.close(socket);

        // Allow address reuse
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        try posix.bind(socket, &addr.any, addr.getOsSockLen());
        try posix.listen(socket, 5);

        var bound_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);
        try posix.getsockname(socket, &bound_addr.any, &addr_len);

        return .{
            .socket = socket,
            .address = bound_addr,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        posix.close(self.socket);
    }

    fn handleClient(client: posix.socket_t) void {
        defer posix.close(client);
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = posix.read(client, &buf) catch break;
            if (n == 0) break;
            _ = posix.write(client, buf[0..n]) catch break;
        }
    }

    fn acceptLoop(self: *Self) void {
        while (self.running) {
            var client_addr: posix.sockaddr = undefined;
            var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

            const client = posix.accept(self.socket, &client_addr, &addr_len) catch continue;
            _ = std.Thread.spawn(.{}, handleClient, .{client}) catch {
                posix.close(client);
            };
        }
    }

    pub fn start(self: *Self) !void {
        self.running = true;
        self.thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
    }

    pub fn stop(self: *Self) void {
        self.running = false;
        // Close socket to unblock accept
        posix.close(self.socket);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    pub fn getAddress(self: *const Self) net.Address {
        return self.address;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Run the event loop briefly (one iteration)
pub fn run_briefly(loop: *TestLoop) void {
    loop.run_once();
}

/// Run until a predicate becomes true
pub fn run_until(loop: *TestLoop, predicate: *const fn () bool, timeout: f64) !void {
    const start = loop.getTime();
    var delay: f64 = 0.001;

    while (!predicate()) {
        if (loop.getTime() - start > timeout) {
            return error.Timeout;
        }
        loop.advance_time(delay);
        loop.run_once();
        delay = @min(delay * 2, 1.0);
    }
}

/// Run one iteration (legacy API)
pub fn run_once(loop: *TestLoop) void {
    loop.run_once();
    loop.stop();
}

/// Create a mock non-blocking socket (returns fd placeholder)
pub fn mock_nonblocking_socket() !posix.socket_t {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, 0);
    return sock;
}

/// Get function source location (for debugging)
pub fn get_function_source(comptime func: anytype) struct { file: []const u8, line: u32 } {
    const loc = @src();
    _ = func;
    return .{ .file = loc.file, .line = loc.line };
}

// ============================================================================
// TestCase - Base class for asyncio tests
// ============================================================================

/// Base test case for asyncio tests
pub const TestCase = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    loop: ?*TestLoop = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.loop) |loop| {
            loop.deinit();
            self.allocator.destroy(loop);
        }
    }

    /// Create a new test loop
    pub fn new_test_loop(self: *Self) !*TestLoop {
        const loop = try self.allocator.create(TestLoop);
        loop.* = TestLoop.init(self.allocator);
        self.loop = loop;
        return loop;
    }

    /// Set the event loop
    pub fn set_event_loop(self: *Self, loop: *TestLoop) void {
        self.loop = loop;
    }

    /// Close the loop and clean up
    pub fn close_loop(self: *Self, loop: *TestLoop) void {
        _ = self;
        loop.close();
    }

    /// Setup before each test
    pub fn setUp(self: *Self) void {
        _ = self;
    }

    /// Teardown after each test
    pub fn tearDown(self: *Self) void {
        if (self.loop) |loop| {
            loop.close();
        }
    }
};

// ============================================================================
// disable_logger - Context manager to disable asyncio logger
// ============================================================================

/// Logger disabler for test isolation
pub const LoggerDisabler = struct {
    old_level: u8 = 0,

    pub fn enter(self: *LoggerDisabler) void {
        // Save current level and set to critical+1
        self.old_level = 0; // In real impl, would save logger level
        // logger.setLevel(CRITICAL + 1)
    }

    pub fn exit(self: *LoggerDisabler) void {
        // Restore old level
        _ = self.old_level;
    }
};

pub fn disable_logger() LoggerDisabler {
    return .{};
}

// ============================================================================
// Tests
// ============================================================================

test "TestSelector" {
    const allocator = std.testing.allocator;
    var selector = TestSelector.init(allocator);
    defer selector.deinit();

    const key = try selector.register(0, 1, null);
    try std.testing.expectEqual(@as(posix.fd_t, 0), key.fd);

    _ = selector.unregister(0);
    try std.testing.expect(selector.keys.count() == 0);
}

test "TestLoop time" {
    const allocator = std.testing.allocator;
    var loop = TestLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expectEqual(@as(f64, 0.0), loop.getTime());
    loop.advance_time(1.0);
    try std.testing.expectEqual(@as(f64, 1.0), loop.getTime());
}

test "TestLoop readers" {
    const allocator = std.testing.allocator;
    var loop = TestLoop.init(allocator);
    defer loop.deinit();

    var handle = Handle{ .callback = undefined };
    try loop.add_reader(5, &handle);
    try loop.assert_reader(5);

    _ = loop.remove_reader(5);
    try loop.assert_no_reader(5);
}

test "MockCallback" {
    const allocator = std.testing.allocator;
    var mock = MockCallback.init(allocator);
    defer mock.deinit();

    try mock.assert_not_called();
    _ = mock.call();
    try mock.assert_called();
    try mock.assert_called_once();
}

test "MockPattern" {
    const pattern = MockPattern.init("hello");
    try std.testing.expect(pattern.matches("hello world"));
    try std.testing.expect(!pattern.matches("goodbye"));
}

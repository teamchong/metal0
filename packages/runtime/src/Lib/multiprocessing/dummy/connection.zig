//! multiprocessing.dummy.connection - Thread-safe queue-based connection
//! Reference: cpython/Lib/multiprocessing/dummy/__init__.py
//!
//! Provides thread-safe connection objects using queues instead of pipes.
//! Used by multiprocessing.dummy for inter-thread communication.

const std = @import("std");

// ============================================================================
// Connection
// ============================================================================

/// CPython: class Connection (Queue-based for threads)
/// A thread-safe connection using queues for send/recv
pub const Connection = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    send_queue: std.ArrayList([]const u8),
    recv_queue: *std.ArrayList([]const u8),
    send_mutex: std.Thread.Mutex,
    recv_mutex: *std.Thread.Mutex,
    send_cond: std.Thread.Condition,
    recv_cond: *std.Thread.Condition,
    closed: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        recv_queue: *std.ArrayList([]const u8),
        recv_mutex: *std.Thread.Mutex,
        recv_cond: *std.Thread.Condition,
    ) Self {
        return .{
            .allocator = allocator,
            .send_queue = .{},
            .recv_queue = recv_queue,
            .send_mutex = .{},
            .recv_mutex = recv_mutex,
            .send_cond = .{},
            .recv_cond = recv_cond,
            .closed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.send_queue.items) |item| {
            self.allocator.free(item);
        }
        self.send_queue.deinit(self.allocator);
    }

    /// Send data through the connection
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.closed) return error.ConnectionClosed;

        self.send_mutex.lock();
        defer self.send_mutex.unlock();

        const copy = try self.allocator.dupe(u8, data);
        try self.send_queue.append(self.allocator, copy);
        self.send_cond.signal();
    }

    /// Receive data from the connection
    pub fn recv(self: *Self, timeout: ?f64) ![]const u8 {
        if (self.closed) return error.ConnectionClosed;

        self.recv_mutex.lock();
        defer self.recv_mutex.unlock();

        while (self.recv_queue.items.len == 0) {
            if (self.closed) return error.ConnectionClosed;
            if (timeout) |t| {
                const ns: u64 = @intFromFloat(t * std.time.ns_per_s);
                const result = self.recv_cond.timedWait(self.recv_mutex, ns);
                if (result == .timed_out) return error.Timeout;
            } else {
                self.recv_cond.wait(self.recv_mutex);
            }
        }

        return self.recv_queue.orderedRemove(0);
    }

    /// Check if data is available
    pub fn poll(self: *Self, timeout: ?f64) !bool {
        if (self.closed) return false;
        _ = timeout;

        self.recv_mutex.lock();
        defer self.recv_mutex.unlock();
        return self.recv_queue.items.len > 0;
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        self.closed = true;
        self.send_cond.broadcast();
        self.recv_cond.broadcast();
    }

    /// Get the send queue (for the other end to receive from)
    pub fn getSendQueue(self: *Self) *std.ArrayList([]const u8) {
        return &self.send_queue;
    }

    pub fn getSendMutex(self: *Self) *std.Thread.Mutex {
        return &self.send_mutex;
    }

    pub fn getSendCond(self: *Self) *std.Thread.Condition {
        return &self.send_cond;
    }
};

// ============================================================================
// Pipe
// ============================================================================

/// CPython: Pipe(duplex=True)
/// Create a pair of connected Connection objects
pub fn Pipe(allocator: std.mem.Allocator, duplex: bool) !struct { *Connection, *Connection } {
    _ = duplex; // Always duplex for thread connections

    // Create shared queues and synchronization primitives
    const conn1 = try allocator.create(Connection);
    const conn2 = try allocator.create(Connection);

    // Initialize conn1 first
    conn1.* = .{
        .allocator = allocator,
        .send_queue = .{},
        .recv_queue = undefined, // Will be set after conn2 init
        .send_mutex = .{},
        .recv_mutex = undefined,
        .send_cond = .{},
        .recv_cond = undefined,
        .closed = false,
    };

    // Initialize conn2
    conn2.* = .{
        .allocator = allocator,
        .send_queue = .{},
        .recv_queue = &conn1.send_queue, // conn2 receives from conn1's send
        .send_mutex = .{},
        .recv_mutex = &conn1.send_mutex,
        .send_cond = .{},
        .recv_cond = &conn1.send_cond,
        .closed = false,
    };

    // Now set conn1's receive to conn2's send
    conn1.recv_queue = &conn2.send_queue;
    conn1.recv_mutex = &conn2.send_mutex;
    conn1.recv_cond = &conn2.send_cond;

    return .{ conn1, conn2 };
}

// ============================================================================
// Tests
// ============================================================================

test "Connection basic" {
    const allocator = std.testing.allocator;

    var queue: std.ArrayList([]const u8) = .{};
    defer queue.deinit(allocator);
    var mutex: std.Thread.Mutex = .{};
    var cond: std.Thread.Condition = .{};

    var conn = Connection.init(allocator, &queue, &mutex, &cond);
    defer conn.deinit();

    try std.testing.expect(!conn.closed);
    conn.close();
    try std.testing.expect(conn.closed);
}

//! test.test_asyncio.test_sock_lowlevel - Tests for low-level socket operations
//! Reference: cpython/Lib/test/test_asyncio/test_sock_lowlevel.py
//!
//! Tests for sock_recv, sock_sendall, sock_connect, sock_accept

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Low-level Socket Operations
// ============================================================================

/// Async socket receive
pub fn sock_recv(
    _: *test_events.EventLoop,
    sock: *MockSocket,
    nbytes: usize,
) ![]const u8 {
    return sock.recv(nbytes);
}

/// Async socket receive into buffer
pub fn sock_recv_into(
    _: *test_events.EventLoop,
    sock: *MockSocket,
    buf: []u8,
) !usize {
    return sock.recv_into(buf);
}

/// Async socket send all
pub fn sock_sendall(
    _: *test_events.EventLoop,
    sock: *MockSocket,
    data: []const u8,
) !void {
    return sock.sendall(data);
}

/// Async socket connect
pub fn sock_connect(
    _: *test_events.EventLoop,
    sock: *MockSocket,
    addr: []const u8,
    port: u16,
) !void {
    return sock.connect(addr, port);
}

/// Async socket accept
pub fn sock_accept(
    allocator: std.mem.Allocator,
    _: *test_events.EventLoop,
    sock: *MockSocket,
) !struct { conn: MockSocket, addr: []const u8 } {
    return sock.accept(allocator);
}

// ============================================================================
// Mock Socket for Testing
// ============================================================================

pub const MockSocket = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _fd: posix.socket_t = 0,
    _recv_buffer: std.ArrayList(u8),
    _send_buffer: std.ArrayList(u8),
    _connected: bool = false,
    _listening: bool = false,
    _blocking: bool = true,
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._recv_buffer = std.ArrayList(u8).init(allocator),
            ._send_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._recv_buffer.deinit();
        self._send_buffer.deinit();
    }

    pub fn recv(self: *Self, nbytes: usize) ![]const u8 {
        if (self._closed) return error.SocketClosed;
        const to_read = @min(nbytes, self._recv_buffer.items.len);
        return self._recv_buffer.items[0..to_read];
    }

    pub fn recv_into(self: *Self, buf: []u8) !usize {
        if (self._closed) return error.SocketClosed;
        const to_read = @min(buf.len, self._recv_buffer.items.len);
        @memcpy(buf[0..to_read], self._recv_buffer.items[0..to_read]);
        return to_read;
    }

    pub fn sendall(self: *Self, data: []const u8) !void {
        if (self._closed) return error.SocketClosed;
        if (!self._connected) return error.NotConnected;
        try self._send_buffer.appendSlice(data);
    }

    pub fn connect(self: *Self, _: []const u8, _: u16) !void {
        if (self._closed) return error.SocketClosed;
        self._connected = true;
    }

    pub fn accept(self: *Self, allocator: std.mem.Allocator) !struct { conn: MockSocket, addr: []const u8 } {
        if (self._closed) return error.SocketClosed;
        if (!self._listening) return error.NotListening;

        var conn = MockSocket.init(allocator);
        conn._connected = true;
        return .{
            .conn = conn,
            .addr = "127.0.0.1",
        };
    }

    pub fn bind(self: *Self, _: []const u8, _: u16) !void {
        if (self._closed) return error.SocketClosed;
    }

    pub fn listen(self: *Self, _: i32) !void {
        if (self._closed) return error.SocketClosed;
        self._listening = true;
    }

    pub fn setblocking(self: *Self, blocking: bool) void {
        self._blocking = blocking;
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        self._connected = false;
        self._listening = false;
    }

    pub fn fileno(self: *const Self) posix.socket_t {
        return self._fd;
    }

    /// Feed data for testing
    pub fn feed_data(self: *Self, data: []const u8) !void {
        try self._recv_buffer.appendSlice(data);
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testMockSocketCreate() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try std.testing.expect(!sock._connected);
    try std.testing.expect(!sock._closed);
}

fn testMockSocketConnect() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.connect("127.0.0.1", 8080);
    try std.testing.expect(sock._connected);
}

fn testMockSocketRecv() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.feed_data("hello world");
    const data = try sock.recv(5);
    try std.testing.expectEqualStrings("hello", data);
}

fn testMockSocketRecvInto() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.feed_data("hello");
    var buf: [10]u8 = undefined;
    const n = try sock.recv_into(&buf);

    try std.testing.expectEqual(@as(usize, 5), n);
}

fn testMockSocketSendall() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.connect("127.0.0.1", 8080);
    try sock.sendall("hello");

    try std.testing.expectEqualStrings("hello", sock._send_buffer.items);
}

fn testMockSocketSendallNotConnected() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    const err = sock.sendall("data");
    try std.testing.expectError(error.NotConnected, err);
}

fn testMockSocketAccept() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.listen(5);
    var result = try sock.accept(allocator);
    defer result.conn.deinit();

    try std.testing.expect(result.conn._connected);
}

fn testSockRecv() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock.feed_data("hello");
    const data = try sock_recv(&loop, &sock, 5);
    try std.testing.expectEqualStrings("hello", data);
}

fn testSockConnect() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    try sock_connect(&loop, &sock, "127.0.0.1", 8080);
    try std.testing.expect(sock._connected);
}

fn testMockSocketClose() !void {
    const allocator = std.testing.allocator;
    var sock = MockSocket.init(allocator);
    defer sock.deinit();

    sock.close();
    try std.testing.expect(sock._closed);

    const err = sock.connect("127.0.0.1", 8080);
    try std.testing.expectError(error.SocketClosed, err);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "MockSocket create" {
    try testMockSocketCreate();
}

test "MockSocket connect" {
    try testMockSocketConnect();
}

test "MockSocket recv" {
    try testMockSocketRecv();
}

test "MockSocket recv_into" {
    try testMockSocketRecvInto();
}

test "MockSocket sendall" {
    try testMockSocketSendall();
}

test "MockSocket sendall not connected" {
    try testMockSocketSendallNotConnected();
}

test "MockSocket accept" {
    try testMockSocketAccept();
}

test "sock_recv" {
    try testSockRecv();
}

test "sock_connect" {
    try testSockConnect();
}

test "MockSocket close" {
    try testMockSocketClose();
}

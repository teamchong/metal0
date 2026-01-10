//! test.test_asyncio.test_server - Tests for asyncio servers
//! Reference: cpython/Lib/test/test_asyncio/test_server.py
//!
//! Tests for Server class and server creation

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_protocols = @import("test_protocols.zig");

// ============================================================================
// Server Implementation
// ============================================================================

/// An asyncio server
pub const Server = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _loop: *test_events.EventLoop,
    _sockets: std.ArrayList(Socket),
    _serving: bool = false,
    _serving_forever: bool = false,
    _closed: bool = false,
    _active_count: usize = 0,

    pub const Socket = struct {
        fd: posix.socket_t,
        addr: []const u8,
        port: u16,
    };

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .allocator = allocator,
            ._loop = loop,
            ._sockets = std.ArrayList(Socket).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._sockets.deinit();
    }

    /// Add a socket to the server
    pub fn add_socket(self: *Self, fd: posix.socket_t, addr: []const u8, port: u16) !void {
        try self._sockets.append(.{
            .fd = fd,
            .addr = addr,
            .port = port,
        });
    }

    /// Get server sockets
    pub fn get_sockets(self: *const Self) []const Socket {
        return self._sockets.items;
    }

    /// Check if server is serving
    pub fn is_serving(self: *const Self) bool {
        return self._serving;
    }

    /// Start serving
    pub fn start_serving(self: *Self) void {
        self._serving = true;
    }

    /// Serve forever
    pub fn serve_forever(self: *Self) void {
        self._serving = true;
        self._serving_forever = true;
    }

    /// Close the server
    pub fn close(self: *Self) void {
        self._serving = false;
        self._serving_forever = false;
        self._closed = true;
    }

    /// Wait for the server to close
    pub fn wait_closed(self: *Self) void {
        while (self._active_count > 0) {
            std.atomic.spinLoopHint();
        }
    }

    /// Get loop
    pub fn get_loop(self: *const Self) *test_events.EventLoop {
        return self._loop;
    }
};

// ============================================================================
// Server Creation Functions
// ============================================================================

/// Create a TCP server
pub fn create_server(
    allocator: std.mem.Allocator,
    loop: *test_events.EventLoop,
    _: *const fn (*test_protocols.Protocol) void,
    host: []const u8,
    port: u16,
) !Server {
    var server = Server.init(allocator, loop);

    // Simulate socket creation
    try server.add_socket(42, host, port);

    return server;
}

/// Create a Unix socket server
pub fn create_unix_server(
    allocator: std.mem.Allocator,
    loop: *test_events.EventLoop,
    _: *const fn (*test_protocols.Protocol) void,
    path: []const u8,
) !Server {
    var server = Server.init(allocator, loop);

    // Simulate Unix socket creation
    try server.add_socket(43, path, 0);

    return server;
}

// ============================================================================
// InetServer - Internet socket server helper
// ============================================================================

pub const InetServer = struct {
    const Self = @This();

    server: Server,
    _backlog: usize = 100,
    _reuse_address: bool = true,
    _reuse_port: bool = false,

    pub fn init(allocator: std.mem.Allocator, loop: *test_events.EventLoop) Self {
        return .{
            .server = Server.init(allocator, loop),
        };
    }

    pub fn deinit(self: *Self) void {
        self.server.deinit();
    }

    pub fn set_backlog(self: *Self, backlog: usize) void {
        self._backlog = backlog;
    }

    pub fn set_reuse_address(self: *Self, reuse: bool) void {
        self._reuse_address = reuse;
    }

    pub fn set_reuse_port(self: *Self, reuse: bool) void {
        self._reuse_port = reuse;
    }

    pub fn bind(self: *Self, host: []const u8, port: u16) !void {
        try self.server.add_socket(44, host, port);
    }

    pub fn listen(self: *Self) void {
        self.server.start_serving();
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testServerCreate() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    try std.testing.expect(!server.is_serving());
    try std.testing.expect(!server._closed);
}

fn testServerAddSocket() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    try server.add_socket(42, "127.0.0.1", 8080);

    const sockets = server.get_sockets();
    try std.testing.expectEqual(@as(usize, 1), sockets.len);
    try std.testing.expectEqual(@as(u16, 8080), sockets[0].port);
}

fn testServerServing() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    try std.testing.expect(!server.is_serving());
    server.start_serving();
    try std.testing.expect(server.is_serving());
}

fn testServerClose() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    server.start_serving();
    server.close();

    try std.testing.expect(!server.is_serving());
    try std.testing.expect(server._closed);
}

fn testCreateServer() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    const proto_factory = struct {
        fn factory(_: *test_protocols.Protocol) void {}
    }.factory;

    var server = try create_server(allocator, &loop, proto_factory, "0.0.0.0", 8080);
    defer server.deinit();

    try std.testing.expectEqual(@as(usize, 1), server.get_sockets().len);
}

fn testInetServer() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = InetServer.init(allocator, &loop);
    defer server.deinit();

    server.set_backlog(200);
    server.set_reuse_address(true);

    try server.bind("0.0.0.0", 8080);
    server.listen();

    try std.testing.expect(server.server.is_serving());
}

fn testServerGetLoop() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    try std.testing.expect(server.get_loop() == &loop);
}

fn testServerServeForever() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var server = Server.init(allocator, &loop);
    defer server.deinit();

    server.serve_forever();
    try std.testing.expect(server._serving_forever);
    try std.testing.expect(server.is_serving());
}

fn testCreateUnixServer() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    const proto_factory = struct {
        fn factory(_: *test_protocols.Protocol) void {}
    }.factory;

    var server = try create_unix_server(allocator, &loop, proto_factory, "/tmp/test.sock");
    defer server.deinit();

    try std.testing.expectEqual(@as(usize, 1), server.get_sockets().len);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Server create" {
    try testServerCreate();
}

test "Server add_socket" {
    try testServerAddSocket();
}

test "Server serving" {
    try testServerServing();
}

test "Server close" {
    try testServerClose();
}

test "create_server" {
    try testCreateServer();
}

test "InetServer" {
    try testInetServer();
}

test "Server get_loop" {
    try testServerGetLoop();
}

test "Server serve_forever" {
    try testServerServeForever();
}

test "create_unix_server" {
    try testCreateUnixServer();
}

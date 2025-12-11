//! CPython source: Lib/socketserver.py
//!
//! Provides classes for implementing network servers.
//!
//! Mirrors: CPython Lib/socketserver.py

const std = @import("std");

// ============================================================================
// BaseServer
// ============================================================================

/// Base class for server implementations
pub fn BaseServer(comptime RequestHandler: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        server_address: std.net.Address,
        request_handler: type,
        shutdown_request: bool,
        is_running: bool,

        pub fn init(allocator: std.mem.Allocator, server_address: std.net.Address) Self {
            return .{
                .allocator = allocator,
                .server_address = server_address,
                .request_handler = RequestHandler,
                .shutdown_request = false,
                .is_running = false,
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Start serving requests
        pub fn serveForever(self: *Self, poll_interval: ?f64) void {
            _ = poll_interval;
            self.is_running = true;
            while (!self.shutdown_request) {
                self.handleRequest() catch break;
            }
            self.is_running = false;
        }

        /// Handle a single request
        pub fn handleRequest(self: *Self) !void {
            _ = self;
            // Would accept and handle request
        }

        /// Shutdown the server
        pub fn shutdown(self: *Self) void {
            self.shutdown_request = true;
        }

        /// Close the server
        pub fn serverClose(self: *Self) void {
            self.shutdown_request = true;
            self.is_running = false;
        }

        /// Called when an error occurs
        pub fn handleError(self: *Self, request: anytype, client_address: anytype) void {
            _ = self;
            _ = request;
            _ = client_address;
            // Would log error
        }

        /// Called before processing request
        pub fn verifyRequest(self: *Self, request: anytype, client_address: anytype) bool {
            _ = self;
            _ = request;
            _ = client_address;
            return true;
        }
    };
}

// ============================================================================
// TCPServer
// ============================================================================

/// TCP server implementation
pub fn TCPServer(comptime RequestHandler: type) type {
    return struct {
        const Self = @This();

        base: BaseServer(RequestHandler),
        socket: ?std.posix.socket_t,
        allow_reuse_address: bool,
        request_queue_size: u32,

        pub const address_family = std.posix.AF.INET;
        pub const socket_type = std.posix.SOCK.STREAM;

        pub fn init(allocator: std.mem.Allocator, server_address: std.net.Address) !Self {
            var self = Self{
                .base = BaseServer(RequestHandler).init(allocator, server_address),
                .socket = null,
                .allow_reuse_address = true,
                .request_queue_size = 5,
            };

            try self.serverBind();
            try self.serverActivate();

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.serverClose();
            self.base.deinit();
        }

        fn serverBind(self: *Self) !void {
            self.socket = try std.posix.socket(address_family, socket_type, 0);

            if (self.allow_reuse_address) {
                try std.posix.setsockopt(self.socket.?, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
            }

            try std.posix.bind(self.socket.?, &self.base.server_address.any, self.base.server_address.getOsSockLen());
        }

        fn serverActivate(self: *Self) !void {
            try std.posix.listen(self.socket.?, @intCast(self.request_queue_size));
        }

        pub fn serverClose(self: *Self) void {
            if (self.socket) |sock| {
                std.posix.close(sock);
                self.socket = null;
            }
            self.base.serverClose();
        }

        pub fn serveForever(self: *Self, poll_interval: ?f64) void {
            self.base.serveForever(poll_interval);
        }

        pub fn handleRequest(self: *Self) !void {
            var client_addr: std.posix.sockaddr = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

            const conn = try std.posix.accept(self.socket.?, &client_addr, &addr_len);
            defer std.posix.close(conn);

            // Create handler instance and process request
            var handler = RequestHandler{
                .server = @ptrCast(&self.base),
                .client_address = std.net.Address.initPosix(&client_addr),
            };

            // If handler has setup method, call it
            if (@hasDecl(RequestHandler, "setup")) {
                handler.setup();
            }

            // Process the request
            if (@hasDecl(RequestHandler, "handle")) {
                handler.handle(conn);
            }

            // If handler has finish method, call it
            if (@hasDecl(RequestHandler, "finish")) {
                handler.finish();
            }
        }

        pub fn shutdown(self: *Self) void {
            self.base.shutdown();
        }

        pub fn fileno(self: *Self) ?std.posix.socket_t {
            return self.socket;
        }
    };
}

// ============================================================================
// UDPServer
// ============================================================================

/// UDP server implementation
pub fn UDPServer(comptime RequestHandler: type) type {
    return struct {
        const Self = @This();

        base: BaseServer(RequestHandler),
        socket: ?std.posix.socket_t,
        allow_reuse_address: bool,
        max_packet_size: usize,

        pub const address_family = std.posix.AF.INET;
        pub const socket_type = std.posix.SOCK.DGRAM;

        pub fn init(allocator: std.mem.Allocator, server_address: std.net.Address) !Self {
            var self = Self{
                .base = BaseServer(RequestHandler).init(allocator, server_address),
                .socket = null,
                .allow_reuse_address = true,
                .max_packet_size = 8192,
            };

            try self.serverBind();

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.serverClose();
            self.base.deinit();
        }

        fn serverBind(self: *Self) !void {
            self.socket = try std.posix.socket(address_family, socket_type, 0);

            if (self.allow_reuse_address) {
                try std.posix.setsockopt(self.socket.?, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
            }

            try std.posix.bind(self.socket.?, &self.base.server_address.any, self.base.server_address.getOsSockLen());
        }

        pub fn serverClose(self: *Self) void {
            if (self.socket) |sock| {
                std.posix.close(sock);
                self.socket = null;
            }
            self.base.serverClose();
        }

        pub fn serveForever(self: *Self, poll_interval: ?f64) void {
            self.base.serveForever(poll_interval);
        }

        pub fn handleRequest(self: *Self) !void {
            var buf: [8192]u8 = undefined;
            var client_addr: std.posix.sockaddr = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

            const n = try std.posix.recvfrom(self.socket.?, &buf, 0, &client_addr, &addr_len);

            // Create handler instance and process request
            var handler = RequestHandler{
                .server = @ptrCast(&self.base),
                .client_address = std.net.Address.initPosix(&client_addr),
            };

            // If handler has setup method, call it
            if (@hasDecl(RequestHandler, "setup")) {
                handler.setup();
            }

            // Process the UDP datagram
            if (@hasDecl(RequestHandler, "handleDatagram")) {
                handler.handleDatagram(buf[0..n], self.socket.?);
            } else if (@hasDecl(RequestHandler, "handle")) {
                handler.handle(self.socket.?);
            }

            // If handler has finish method, call it
            if (@hasDecl(RequestHandler, "finish")) {
                handler.finish();
            }
        }

        pub fn shutdown(self: *Self) void {
            self.base.shutdown();
        }

        pub fn fileno(self: *Self) ?std.posix.socket_t {
            return self.socket;
        }
    };
}

// ============================================================================
// Request Handlers
// ============================================================================

/// Base request handler
pub const BaseRequestHandler = struct {
    const Self = @This();

    request: ?*anyopaque,
    client_address: ?std.net.Address,
    server: ?*anyopaque,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        var self = Self{
            .request = request,
            .client_address = client_address,
            .server = server,
        };
        self.setup();
        self.handle();
        self.finish();
        return self;
    }

    pub fn setup(self: *Self) void {
        _ = self;
    }

    pub fn handle(self: *Self) void {
        _ = self;
    }

    pub fn finish(self: *Self) void {
        _ = self;
    }
};

/// Stream request handler (for TCP)
pub const StreamRequestHandler = struct {
    const Self = @This();

    base: BaseRequestHandler,
    rfile: ?std.fs.File,
    wfile: ?std.fs.File,
    rbufsize: usize,
    wbufsize: usize,
    timeout: ?f64,
    disable_nagle_algorithm: bool,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        return .{
            .base = BaseRequestHandler.init(request, client_address, server),
            .rfile = null,
            .wfile = null,
            .rbufsize = 0, // Unbuffered
            .wbufsize = 0, // Unbuffered
            .timeout = null,
            .disable_nagle_algorithm = false,
        };
    }

    pub fn setup(self: *Self) void {
        self.base.setup();
        // Would set up buffered I/O
    }

    pub fn finish(self: *Self) void {
        // Would flush and close files
        self.base.finish();
    }
};

/// Datagram request handler (for UDP)
pub const DatagramRequestHandler = struct {
    const Self = @This();

    base: BaseRequestHandler,
    packet: ?[]const u8,
    socket: ?std.posix.socket_t,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        return .{
            .base = BaseRequestHandler.init(request, client_address, server),
            .packet = null,
            .socket = null,
        };
    }
};

// ============================================================================
// Mixin Classes
// ============================================================================

/// Mixin to add forking capability
pub fn ForkingMixIn(comptime ServerType: type) type {
    return struct {
        const Self = @This();

        server: ServerType,
        timeout: ?f64,
        active_children: std.ArrayList(std.posix.pid_t),
        max_children: u32,
        block_on_close: bool,

        pub fn init(allocator: std.mem.Allocator, server: ServerType) Self {
            return .{
                .server = server,
                .timeout = null,
                .active_children = std.ArrayList(std.posix.pid_t).init(allocator),
                .max_children = 40,
                .block_on_close = true,
            };
        }

        pub fn deinit(self: *Self) void {
            self.active_children.deinit();
        }

        pub fn collectChildren(self: *Self, blocking: bool) void {
            _ = self;
            _ = blocking;
            // Would wait for child processes
        }

        pub fn processRequest(self: *Self) !void {
            _ = self;
            // Would fork and handle in child
        }
    };
}

/// Mixin to add threading capability
pub fn ThreadingMixIn(comptime ServerType: type) type {
    return struct {
        const Self = @This();

        server: ServerType,
        daemon_threads: bool,
        block_on_close: bool,

        pub fn init(server: ServerType) Self {
            return .{
                .server = server,
                .daemon_threads = false,
                .block_on_close = true,
            };
        }

        pub fn processRequest(self: *Self) !void {
            _ = self;
            // Would spawn thread to handle request
        }
    };
}

// ============================================================================
// Concrete Server Types
// ============================================================================

/// Forking TCP server
pub fn ForkingTCPServer(comptime RequestHandler: type) type {
    return ForkingMixIn(TCPServer(RequestHandler));
}

/// Forking UDP server
pub fn ForkingUDPServer(comptime RequestHandler: type) type {
    return ForkingMixIn(UDPServer(RequestHandler));
}

/// Threading TCP server
pub fn ThreadingTCPServer(comptime RequestHandler: type) type {
    return ThreadingMixIn(TCPServer(RequestHandler));
}

/// Threading UDP server
pub fn ThreadingUDPServer(comptime RequestHandler: type) type {
    return ThreadingMixIn(UDPServer(RequestHandler));
}

// ============================================================================
// Tests
// ============================================================================

test "BaseRequestHandler" {
    const handler = BaseRequestHandler.init(null, null, null);
    try std.testing.expect(handler.request == null);
}

test "StreamRequestHandler" {
    const handler = StreamRequestHandler.init(null, null, null);
    try std.testing.expect(handler.rfile == null);
    try std.testing.expectEqual(@as(usize, 0), handler.rbufsize);
}

test "DatagramRequestHandler" {
    const handler = DatagramRequestHandler.init(null, null, null);
    try std.testing.expect(handler.packet == null);
}

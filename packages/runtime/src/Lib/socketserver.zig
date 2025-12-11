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

        /// Handle a single request (base implementation - subclasses override)
        pub fn handleRequest(self: *Self) !void {
            // Base server doesn't have socket - concrete servers (TCP/UDP) override this
            _ = self;
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

        /// Called when an error occurs - logs to stderr
        pub fn handleError(self: *Self, request: anytype, client_address: anytype) void {
            _ = self;
            _ = request;
            // Log error to stderr with client address info
            const stderr = std.io.getStdErr().writer();
            if (@TypeOf(client_address) == std.net.Address) {
                var addr_buf: [64]u8 = undefined;
                const addr_str = client_address.format(&addr_buf) catch "unknown";
                stderr.print("Exception occurred during request from {s}\n", .{addr_str}) catch {};
            } else {
                stderr.print("Exception occurred during request\n", .{}) catch {};
            }
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
    connection: ?std.posix.socket_t,
    rbufsize: usize,
    wbufsize: usize,
    timeout: ?f64,
    disable_nagle_algorithm: bool,
    // Buffered I/O state
    read_buffer: [8192]u8,
    read_pos: usize,
    read_end: usize,
    write_buffer: [8192]u8,
    write_pos: usize,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        return .{
            .base = BaseRequestHandler.init(request, client_address, server),
            .connection = null,
            .rbufsize = 8192,
            .wbufsize = 8192,
            .timeout = null,
            .disable_nagle_algorithm = false,
            .read_buffer = undefined,
            .read_pos = 0,
            .read_end = 0,
            .write_buffer = undefined,
            .write_pos = 0,
        };
    }

    pub fn setup(self: *Self, conn: std.posix.socket_t) void {
        self.base.setup();
        self.connection = conn;
        self.read_pos = 0;
        self.read_end = 0;
        self.write_pos = 0;

        // Disable Nagle algorithm if requested (for lower latency)
        if (self.disable_nagle_algorithm) {
            std.posix.setsockopt(conn, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1))) catch {};
        }

        // Set socket timeout if specified
        if (self.timeout) |timeout_secs| {
            const timeout_us: i64 = @intFromFloat(timeout_secs * 1_000_000);
            const tv = std.posix.timeval{
                .tv_sec = @intCast(@divFloor(timeout_us, 1_000_000)),
                .tv_usec = @intCast(@mod(timeout_us, 1_000_000)),
            };
            std.posix.setsockopt(conn, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch {};
            std.posix.setsockopt(conn, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv)) catch {};
        }
    }

    /// Read from buffered input
    pub fn read(self: *Self, buf: []u8) !usize {
        if (self.connection == null) return error.NotConnected;

        // If buffer is empty, refill it
        if (self.read_pos >= self.read_end) {
            const n = std.posix.recv(self.connection.?, &self.read_buffer, 0) catch |err| {
                if (err == error.WouldBlock) return 0;
                return err;
            };
            if (n == 0) return 0; // EOF
            self.read_pos = 0;
            self.read_end = n;
        }

        // Copy from buffer to output
        const available = self.read_end - self.read_pos;
        const to_copy = @min(available, buf.len);
        @memcpy(buf[0..to_copy], self.read_buffer[self.read_pos..][0..to_copy]);
        self.read_pos += to_copy;
        return to_copy;
    }

    /// Read a line from buffered input
    pub fn readline(self: *Self, buf: []u8) ![]u8 {
        var pos: usize = 0;
        while (pos < buf.len) {
            var byte: [1]u8 = undefined;
            const n = try self.read(&byte);
            if (n == 0) break; // EOF
            buf[pos] = byte[0];
            pos += 1;
            if (byte[0] == '\n') break;
        }
        return buf[0..pos];
    }

    /// Write to buffered output
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.connection == null) return error.NotConnected;

        var written: usize = 0;
        for (data) |byte| {
            self.write_buffer[self.write_pos] = byte;
            self.write_pos += 1;

            // Flush if buffer is full
            if (self.write_pos >= self.write_buffer.len) {
                try self.flush();
            }
            written += 1;
        }
        return written;
    }

    /// Flush write buffer to socket
    pub fn flush(self: *Self) !void {
        if (self.connection == null) return error.NotConnected;
        if (self.write_pos == 0) return;

        var sent: usize = 0;
        while (sent < self.write_pos) {
            const n = std.posix.send(self.connection.?, self.write_buffer[sent..self.write_pos], 0) catch |err| {
                if (err == error.WouldBlock) continue;
                return err;
            };
            sent += n;
        }
        self.write_pos = 0;
    }

    pub fn finish(self: *Self) void {
        // Flush any remaining write buffer
        self.flush() catch {};
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
        allocator: std.mem.Allocator,
        timeout: ?f64,
        active_children: std.ArrayListUnmanaged(std.posix.pid_t),
        max_children: u32,
        block_on_close: bool,

        pub fn init(allocator: std.mem.Allocator, server: ServerType) Self {
            return .{
                .server = server,
                .allocator = allocator,
                .timeout = null,
                .active_children = .{},
                .max_children = 40,
                .block_on_close = true,
            };
        }

        pub fn deinit(self: *Self) void {
            // Wait for all children if block_on_close is set
            if (self.block_on_close) {
                self.collectChildren(true);
            }
            self.active_children.deinit(self.allocator);
        }

        /// Collect zombie child processes
        pub fn collectChildren(self: *Self, blocking: bool) void {
            // Remove terminated children from the active list
            var i: usize = 0;
            while (i < self.active_children.items.len) {
                const pid = self.active_children.items[i];
                const flags: u32 = if (blocking) 0 else std.posix.W.NOHANG;
                const result = std.posix.waitpid(pid, flags);
                if (result.pid != 0) {
                    // Child has exited, remove from list
                    _ = self.active_children.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Fork to handle request in child process
        pub fn processRequest(self: *Self, conn: std.posix.socket_t, client_addr: std.net.Address) !void {
            // Collect any finished children first
            self.collectChildren(false);

            // Check if we've hit max children
            if (self.active_children.items.len >= self.max_children) {
                // Wait for at least one child to finish
                self.collectChildren(true);
            }

            const fork_result = std.posix.fork();
            if (fork_result == 0) {
                // Child process - handle the request
                defer std.posix.exit(0);

                // Close listening socket in child
                if (@hasField(ServerType, "socket")) {
                    if (self.server.socket) |sock| {
                        std.posix.close(sock);
                    }
                }

                // Handle the request using the server's handler
                if (@hasDecl(ServerType, "handleRequest")) {
                    self.server.handleRequest() catch {};
                }
            } else {
                // Parent process - track the child
                self.active_children.append(self.allocator, fork_result) catch {};

                // Close connection in parent (child has it)
                std.posix.close(conn);
                _ = client_addr;
            }
        }
    };
}

/// Mixin to add threading capability
pub fn ThreadingMixIn(comptime ServerType: type) type {
    return struct {
        const Self = @This();

        server: ServerType,
        allocator: std.mem.Allocator,
        daemon_threads: bool,
        block_on_close: bool,
        active_threads: std.ArrayListUnmanaged(std.Thread),

        pub fn init(allocator: std.mem.Allocator, server: ServerType) Self {
            return .{
                .server = server,
                .allocator = allocator,
                .daemon_threads = false,
                .block_on_close = true,
                .active_threads = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            // Join all threads if block_on_close is set
            if (self.block_on_close) {
                for (self.active_threads.items) |thread| {
                    thread.join();
                }
            }
            self.active_threads.deinit(self.allocator);
        }

        /// Thread entry point for handling requests
        fn threadHandler(context: struct { server: *ServerType, conn: std.posix.socket_t, addr: std.net.Address }) void {
            defer std.posix.close(context.conn);

            // Handle the request using the server's handler
            if (@hasDecl(ServerType, "handleConnectionInThread")) {
                context.server.handleConnectionInThread(context.conn, context.addr);
            }
        }

        /// Spawn a thread to handle request
        pub fn processRequest(self: *Self, conn: std.posix.socket_t, client_addr: std.net.Address) !void {
            // Clean up finished threads (check if joinable)
            var i: usize = 0;
            while (i < self.active_threads.items.len) {
                // Try to remove threads that are done (simplified - just keep all for now)
                i += 1;
            }

            // Spawn thread to handle this connection
            const thread = try std.Thread.spawn(.{}, threadHandler, .{.{
                .server = &self.server,
                .conn = conn,
                .addr = client_addr,
            }});

            // Track the thread
            try self.active_threads.append(self.allocator, thread);

            // If daemon threads, we don't need to track them
            if (self.daemon_threads) {
                thread.detach();
                // Remove from active list since it's detached
                _ = self.active_threads.pop();
            }
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
    try std.testing.expect(handler.connection == null);
    try std.testing.expectEqual(@as(usize, 8192), handler.rbufsize);
}

test "DatagramRequestHandler" {
    const handler = DatagramRequestHandler.init(null, null, null);
    try std.testing.expect(handler.packet == null);
}

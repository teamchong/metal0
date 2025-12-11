//! TCP server implementation
//!
//! Mirrors: CPython Lib/socketserver.py (TCPServer)

const std = @import("std");
const types = @import("types.zig");

// ============================================================================
// TCPServer
// ============================================================================

/// TCP server implementation
pub fn TCPServer(comptime RequestHandler: type) type {
    return struct {
        const Self = @This();

        base: types.BaseServer(RequestHandler),
        socket: ?std.posix.socket_t,
        allow_reuse_address: bool,
        request_queue_size: u32,

        pub const address_family = std.posix.AF.INET;
        pub const socket_type = std.posix.SOCK.STREAM;

        pub fn init(allocator: std.mem.Allocator, server_address: std.net.Address) !Self {
            var self = Self{
                .base = types.BaseServer(RequestHandler).init(allocator, server_address),
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

//! Core types and BaseServer implementation
//!
//! Mirrors: CPython Lib/socketserver.py (BaseServer)

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

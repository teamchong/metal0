//! Mixin classes for adding forking/threading capabilities
//!
//! Mirrors: CPython Lib/socketserver.py (ForkingMixIn, ThreadingMixIn)

const std = @import("std");

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
                self.active_children.append(self.allocator, fork_result) catch unreachable;

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

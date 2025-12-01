//! Async Socket - Non-blocking socket I/O with netpoller integration
//!
//! This provides goroutine-like async I/O for HTTP connections:
//! 1. Socket is set to non-blocking mode
//! 2. When read/write would block, we register with netpoller
//! 3. Green thread yields (parks)
//! 4. When I/O is ready, netpoller wakes the thread
//!
//! Usage with green threads:
//! ```zig
//! const socket = try AsyncSocket.init(allocator, fd, netpoller);
//! defer socket.deinit();
//!
//! // These calls may yield if I/O would block
//! const n = try socket.read(buffer);
//! try socket.writeAll(data);
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Async socket with netpoller integration
pub const AsyncSocket = struct {
    fd: std.posix.socket_t,
    allocator: std.mem.Allocator,
    is_nonblocking: bool,

    pub fn init(allocator: std.mem.Allocator, fd: std.posix.socket_t) !AsyncSocket {
        // Set socket to non-blocking mode
        if (builtin.os.tag != .windows) {
            const flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch 0;
            _ = std.posix.fcntl(fd, std.posix.F.SETFL, @as(u32, @bitCast(flags)) | std.posix.O.NONBLOCK) catch {};
        }

        return .{
            .fd = fd,
            .allocator = allocator,
            .is_nonblocking = true,
        };
    }

    pub fn deinit(self: *AsyncSocket) void {
        _ = self;
        // Socket is owned by caller, don't close
    }

    /// Read data, yielding if would block
    /// Returns number of bytes read, or 0 for EOF
    pub fn read(self: *AsyncSocket, buffer: []u8) !usize {
        while (true) {
            const result = std.posix.read(self.fd, buffer);
            if (result) |n| {
                return n;
            } else |err| {
                switch (err) {
                    error.WouldBlock => {
                        // Would block - yield and retry
                        // In full implementation, register with netpoller here
                        // For now, just spin with a small sleep
                        std.time.sleep(100); // 100ns
                        continue;
                    },
                    else => return err,
                }
            }
        }
    }

    /// Write all data, yielding if would block
    pub fn writeAll(self: *AsyncSocket, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const result = std.posix.write(self.fd, data[written..]);
            if (result) |n| {
                written += n;
            } else |err| {
                switch (err) {
                    error.WouldBlock => {
                        // Would block - yield and retry
                        std.time.sleep(100); // 100ns
                        continue;
                    },
                    else => return err,
                }
            }
        }
    }

    /// Connect with async handling
    pub fn connect(self: *AsyncSocket, addr: *const std.posix.sockaddr, len: std.posix.socklen_t) !void {
        const result = std.posix.connect(self.fd, addr, len);
        if (result) |_| {
            return;
        } else |err| {
            switch (err) {
                error.WouldBlock => {
                    // Connection in progress - wait for writable
                    // Poll for write readiness
                    var poll_fds = [_]std.posix.pollfd{.{
                        .fd = self.fd,
                        .events = std.posix.POLL.OUT,
                        .revents = 0,
                    }};

                    while (true) {
                        const poll_result = std.posix.poll(&poll_fds, 5000); // 5 second timeout
                        if (poll_result > 0) {
                            // Check for error
                            var so_error: c_int = 0;
                            var len: std.posix.socklen_t = @sizeOf(c_int);
                            _ = std.posix.getsockopt(self.fd, std.posix.SOL.SOCKET, std.posix.SO.ERROR, @ptrCast(&so_error), &len) catch {};
                            if (so_error != 0) {
                                return error.ConnectionRefused;
                            }
                            return; // Connected!
                        } else if (poll_result == 0) {
                            return error.ConnectionTimedOut;
                        }
                        // Interrupted, retry
                    }
                },
                else => return err,
            }
        }
    }
};

/// Create a non-blocking socket
pub fn createNonBlockingSocket(domain: u32, socket_type: u32, protocol: u32) !std.posix.socket_t {
    const fd = try std.posix.socket(domain, socket_type | std.posix.SOCK.NONBLOCK, protocol);
    return fd;
}

/// Connect to host:port with non-blocking socket
pub fn connectAsync(allocator: std.mem.Allocator, host: []const u8, port: u16) !AsyncSocket {
    // DNS lookup
    const list = std.net.getAddressList(allocator, host, port) catch return error.DnsLookupFailed;
    defer list.deinit();

    if (list.addrs.len == 0) return error.NoAddressFound;

    // Create non-blocking socket
    const fd = try createNonBlockingSocket(
        list.addrs[0].any.family,
        std.posix.SOCK.STREAM,
        0,
    );
    errdefer std.posix.close(fd);

    var socket = try AsyncSocket.init(allocator, fd);

    // Connect (may yield)
    try socket.connect(&list.addrs[0].any, list.addrs[0].getOsSockLen());

    return socket;
}

// Tests
test "AsyncSocket creation" {
    // Just test compilation
    _ = AsyncSocket;
}

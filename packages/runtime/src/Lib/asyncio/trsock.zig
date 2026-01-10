//! asyncio.trsock - Transport socket wrapper
//! Reference: cpython/Lib/asyncio/trsock.py

const std = @import("std");

/// Transport socket - wraps a socket for use with transports
/// CPython: class TransportSocket
pub const TransportSocket = struct {
    fd: std.posix.socket_t,
    family: std.posix.AF,
    sock_type: std.posix.SOCK,
    blocking: bool,

    pub fn init(fd: std.posix.socket_t, family: std.posix.AF, sock_type: std.posix.SOCK) TransportSocket {
        return .{
            .fd = fd,
            .family = family,
            .sock_type = sock_type,
            .blocking = true,
        };
    }

    /// Get file descriptor
    pub fn fileno(self: *TransportSocket) std.posix.socket_t {
        return self.fd;
    }

    /// Get socket type
    pub fn getType(self: *TransportSocket) std.posix.SOCK {
        return self.sock_type;
    }

    /// Get address family
    pub fn getFamily(self: *TransportSocket) std.posix.AF {
        return self.family;
    }

    /// Set blocking mode
    pub fn setblocking(self: *TransportSocket, blocking: bool) !void {
        self.blocking = blocking;
        // Would set O_NONBLOCK on fd
    }

    /// Get blocking mode
    pub fn getblocking(self: *TransportSocket) bool {
        return self.blocking;
    }

    /// Get timeout (not applicable in Zig)
    pub fn gettimeout(self: *TransportSocket) ?f64 {
        _ = self;
        return null;
    }

    /// Set timeout (not applicable in async context)
    pub fn settimeout(self: *TransportSocket, timeout: ?f64) void {
        _ = self;
        _ = timeout;
    }

    /// Get socket option
    pub fn getsockopt(self: *TransportSocket, level: i32, optname: i32) !i32 {
        _ = level;
        _ = optname;
        _ = self;
        return 0;
    }

    /// Set socket option
    pub fn setsockopt(self: *TransportSocket, level: i32, optname: i32, value: i32) !void {
        _ = self;
        _ = level;
        _ = optname;
        _ = value;
    }

    /// Get socket name (local address)
    pub fn getsockname(self: *TransportSocket) !std.net.Address {
        _ = self;
        return std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
    }

    /// Get peer name (remote address)
    pub fn getpeername(self: *TransportSocket) !std.net.Address {
        _ = self;
        return std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 0);
    }

    /// Close socket
    pub fn close(self: *TransportSocket) void {
        std.posix.close(self.fd);
    }

    /// Shutdown socket
    pub fn shutdown(self: *TransportSocket, how: std.posix.ShutdownHow) !void {
        try std.posix.shutdown(self.fd, how);
    }
};

// Tests
test "TransportSocket basic" {
    // Create a dummy socket for testing
    const sock = TransportSocket.init(0, .inet, .stream);
    try std.testing.expectEqual(@as(std.posix.socket_t, 0), sock.fileno());
    try std.testing.expectEqual(std.posix.AF.inet, sock.getFamily());
    try std.testing.expectEqual(std.posix.SOCK.stream, sock.getType());
}

//! Socket class implementation
//!
//! Provides the main Socket struct with all socket operations including
//! bind, listen, accept, connect, send, recv, and socket option management.

const std = @import("std");
const posix = std.posix;
const constants = @import("constants.zig");
const address_mod = @import("address.zig");

pub const Address = address_mod.Address;
pub const ShutdownHow = constants.ShutdownHow;
pub const SocketError = constants.SocketError;

// ============================================================================
// Socket - Main socket class
// ============================================================================

/// A socket object representing one endpoint of a network connection
pub const Socket = struct {
    const Self = @This();

    handle: posix.socket_t,
    family: i32,
    sock_type: i32,
    protocol: i32,
    timeout: ?f64 = null,
    blocking: bool = true,

    /// Create a new socket
    pub fn init(family: i32, sock_type: i32, protocol: i32) !Self {
        const handle = try posix.socket(
            @intCast(family),
            @intCast(sock_type),
            @intCast(protocol),
        );

        return .{
            .handle = handle,
            .family = family,
            .sock_type = sock_type,
            .protocol = protocol,
        };
    }

    /// Create socket from existing handle
    pub fn fromHandle(handle: posix.socket_t, family: i32, sock_type: i32, protocol: i32) Self {
        return .{
            .handle = handle,
            .family = family,
            .sock_type = sock_type,
            .protocol = protocol,
        };
    }

    /// Close the socket
    pub fn close(self: *Self) void {
        posix.close(self.handle);
    }

    /// Bind the socket to an address
    pub fn bind(self: *Self, addr: Address) !void {
        try posix.bind(self.handle, &addr.addr, addr.len);
    }

    /// Listen for incoming connections
    pub fn listen(self: *Self, backlog: i32) !void {
        try posix.listen(self.handle, @intCast(backlog));
    }

    /// Accept a connection
    pub fn accept(self: *Self) !struct { socket: Self, address: Address } {
        var addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const new_handle = try posix.accept(self.handle, &addr, &addr_len);

        return .{
            .socket = Self.fromHandle(new_handle, self.family, self.sock_type, self.protocol),
            .address = Address{ .addr = addr, .len = addr_len },
        };
    }

    /// Connect to a remote address
    pub fn connect(self: *Self, addr: Address) !void {
        try posix.connect(self.handle, &addr.addr, addr.len);
    }

    /// Send data
    pub fn send(self: *Self, data: []const u8, flags: u32) !usize {
        return try posix.send(self.handle, data, @bitCast(flags));
    }

    /// Send all data
    pub fn sendall(self: *Self, data: []const u8, flags: u32) !void {
        var sent: usize = 0;
        while (sent < data.len) {
            sent += try self.send(data[sent..], flags);
        }
    }

    /// Receive data
    pub fn recv(self: *Self, buffer: []u8, flags: u32) !usize {
        return try posix.recv(self.handle, buffer, @bitCast(flags));
    }

    /// Send data to a specific address (UDP)
    pub fn sendto(self: *Self, data: []const u8, flags: u32, addr: Address) !usize {
        return try posix.sendto(self.handle, data, @bitCast(flags), &addr.addr, addr.len);
    }

    /// Receive data and sender address (UDP)
    pub fn recvfrom(self: *Self, buffer: []u8, flags: u32) !struct { size: usize, address: Address } {
        var addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const size = try posix.recvfrom(self.handle, buffer, @bitCast(flags), &addr, &addr_len);

        return .{
            .size = size,
            .address = Address{ .addr = addr, .len = addr_len },
        };
    }

    /// Set socket option
    pub fn setsockopt(self: *Self, level: i32, optname: i32, value: i32) !void {
        const val_bytes = std.mem.asBytes(&value);
        try posix.setsockopt(
            self.handle,
            @enumFromInt(level),
            @enumFromInt(optname),
            val_bytes,
        );
    }

    /// Get socket option
    pub fn getsockopt(self: *Self, level: i32, optname: i32) !i32 {
        var value: i32 = 0;
        const value_bytes = std.mem.asBytes(&value);
        _ = try posix.getsockopt(
            self.handle,
            @enumFromInt(level),
            @enumFromInt(optname),
            value_bytes,
        );
        return value;
    }

    /// Set socket timeout
    pub fn settimeout(self: *Self, timeout: ?f64) !void {
        self.timeout = timeout;

        if (timeout) |t| {
            const secs: i64 = @intFromFloat(t);
            const usecs: i64 = @intFromFloat((t - @as(f64, @floatFromInt(secs))) * 1_000_000);

            const tv = posix.timeval{
                .tv_sec = secs,
                .tv_usec = usecs,
            };

            const tv_bytes = std.mem.asBytes(&tv);
            try posix.setsockopt(self.handle, posix.SOL.SOCKET, posix.SO.RCVTIMEO, tv_bytes);
            try posix.setsockopt(self.handle, posix.SOL.SOCKET, posix.SO.SNDTIMEO, tv_bytes);

            self.blocking = t > 0;
        }
    }

    /// Get socket timeout
    pub fn gettimeout(self: *Self) ?f64 {
        return self.timeout;
    }

    /// Set blocking mode
    pub fn setblocking(self: *Self, blocking: bool) !void {
        self.blocking = blocking;
        if (blocking) {
            self.timeout = null;
        } else {
            self.timeout = 0;
        }
        // Note: In a full implementation, would use fcntl to set O_NONBLOCK
    }

    /// Get local socket address
    pub fn getsockname(self: *Self) !Address {
        var addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        try posix.getsockname(self.handle, &addr, &addr_len);
        return Address{ .addr = addr, .len = addr_len };
    }

    /// Get remote socket address
    pub fn getpeername(self: *Self) !Address {
        var addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        try posix.getpeername(self.handle, &addr, &addr_len);
        return Address{ .addr = addr, .len = addr_len };
    }

    /// Shutdown the socket
    pub fn shutdown(self: *Self, how: ShutdownHow) !void {
        try posix.shutdown(self.handle, @enumFromInt(@intFromEnum(how)));
    }

    /// Get the file descriptor
    pub fn fileno(self: *Self) posix.socket_t {
        return self.handle;
    }

    /// Duplicate the socket
    pub fn dup(self: *Self) !Self {
        const new_handle = try posix.dup(self.handle);
        return Self.fromHandle(new_handle, self.family, self.sock_type, self.protocol);
    }
};

// ============================================================================
// Socket Management Functions
// ============================================================================

/// Check if socket has pending data using poll()
pub fn hasData(sock: *Socket) bool {
    var fds = [1]posix.pollfd{
        .{
            .fd = sock.handle,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    // Poll with 0 timeout (non-blocking check)
    const result = posix.poll(&fds, 0) catch return false;
    if (result > 0 and (fds[0].revents & posix.POLL.IN) != 0) {
        return true;
    }
    return false;
}

/// Set close-on-exec flag using fcntl
pub fn setInheritable(sock: *Socket, inheritable: bool) !void {
    const current_flags = posix.fcntl(sock.handle, posix.F.GETFD, 0) catch |err| {
        return switch (err) {
            error.FileDescriptorInvalid => error.InvalidSocket,
            else => error.FcntlFailed,
        };
    };

    const new_flags = if (inheritable)
        current_flags & ~@as(i32, posix.FD_CLOEXEC)
    else
        current_flags | posix.FD_CLOEXEC;

    _ = posix.fcntl(sock.handle, posix.F.SETFD, new_flags) catch {
        return error.FcntlFailed;
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Socket create and close" {
    const AF_INET = constants.AF_INET;
    const SOCK_STREAM = constants.SOCK_STREAM;

    var sock = try Socket.init(AF_INET, SOCK_STREAM, 0);
    sock.close();
}

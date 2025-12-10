//! CPython source: Lib/socket.py
//!
//! Provides access to the BSD socket interface.
//!
//! Mirrors: CPython Lib/socket.py

const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const posix = std.posix;
const net = std.net;

// ============================================================================
// Address Families
// ============================================================================

pub const AF_UNSPEC = posix.AF.UNSPEC;
pub const AF_UNIX = posix.AF.UNIX;
pub const AF_INET = posix.AF.INET;
pub const AF_INET6 = posix.AF.INET6;

// Platform-specific address families
pub const AF_LOCAL = AF_UNIX;

// ============================================================================
// Socket Types
// ============================================================================

pub const SOCK_STREAM = posix.SOCK.STREAM;
pub const SOCK_DGRAM = posix.SOCK.DGRAM;
pub const SOCK_RAW = posix.SOCK.RAW;
pub const SOCK_SEQPACKET = posix.SOCK.SEQPACKET;

// ============================================================================
// Protocol Numbers
// ============================================================================

pub const IPPROTO_IP = 0;
pub const IPPROTO_ICMP = 1;
pub const IPPROTO_TCP = 6;
pub const IPPROTO_UDP = 17;
pub const IPPROTO_IPV6 = 41;

// ============================================================================
// Socket Options
// ============================================================================

pub const SOL_SOCKET = posix.SOL.SOCKET;

pub const SO_REUSEADDR = posix.SO.REUSEADDR;
pub const SO_KEEPALIVE = posix.SO.KEEPALIVE;
pub const SO_BROADCAST = posix.SO.BROADCAST;
pub const SO_LINGER = posix.SO.LINGER;
pub const SO_RCVBUF = posix.SO.RCVBUF;
pub const SO_SNDBUF = posix.SO.SNDBUF;
pub const SO_RCVTIMEO = posix.SO.RCVTIMEO;
pub const SO_SNDTIMEO = posix.SO.SNDTIMEO;

// TCP options
pub const IPPROTO_TCP_CONST = 6;
pub const TCP_NODELAY = 1;

// ============================================================================
// Special Constants
// ============================================================================

pub const INADDR_ANY: u32 = 0;
pub const INADDR_BROADCAST: u32 = 0xFFFFFFFF;
pub const INADDR_LOOPBACK: u32 = 0x7F000001;

/// Default backlog for listen()
pub const SOMAXCONN = 128;

/// Special timeout values
pub const TIMEOUT_NONE: ?f64 = null;
pub const TIMEOUT_DEFAULT: f64 = -1;

// ============================================================================
// Error codes
// ============================================================================

pub const SocketError = error{
    AddressInUse,
    ConnectionRefused,
    ConnectionReset,
    NetworkUnreachable,
    HostUnreachable,
    TimedOut,
    WouldBlock,
    NotConnected,
    InvalidArgument,
    PermissionDenied,
    SocketNotBound,
    AlreadyConnected,
    OperationNotSupported,
};

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
            @enumFromInt(family),
            @enumFromInt(sock_type),
            @enumFromInt(protocol),
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
    pub fn bind(self: *Self, address: Address) !void {
        try posix.bind(self.handle, &address.addr, address.len);
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
    pub fn connect(self: *Self, address: Address) !void {
        try posix.connect(self.handle, &address.addr, address.len);
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
    pub fn sendto(self: *Self, data: []const u8, flags: u32, address: Address) !usize {
        return try posix.sendto(self.handle, data, @bitCast(flags), &address.addr, address.len);
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
        var value_bytes = std.mem.asBytes(&value);
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

/// Shutdown direction
pub const ShutdownHow = enum(i32) {
    SHUT_RD = 0,
    SHUT_WR = 1,
    SHUT_RDWR = 2,
};

// ============================================================================
// Address - Socket address wrapper
// ============================================================================

/// Socket address
pub const Address = struct {
    addr: posix.sockaddr,
    len: posix.socklen_t,

    /// Create an IPv4 address
    pub fn inet4(ip: []const u8, port: u16) !Address {
        var addr: posix.sockaddr.in = undefined;
        addr.family = posix.AF.INET;
        addr.port = std.mem.nativeToBig(u16, port);

        // Parse IP address
        const parsed = try parseIpv4(ip);
        addr.addr = parsed;

        return Address{
            .addr = @bitCast(addr),
            .len = @sizeOf(posix.sockaddr.in),
        };
    }

    /// Create an IPv6 address
    pub fn inet6(ip: []const u8, port: u16) !Address {
        var addr: posix.sockaddr.in6 = undefined;
        addr.family = posix.AF.INET6;
        addr.port = std.mem.nativeToBig(u16, port);
        addr.flowinfo = 0;
        addr.scope_id = 0;

        // Parse IP address
        const parsed = try parseIpv6(ip);
        addr.addr = parsed;

        return Address{
            .addr = @bitCast(addr),
            .len = @sizeOf(posix.sockaddr.in6),
        };
    }

    /// Get the port number
    pub fn getPort(self: *const Address) u16 {
        if (self.addr.family == posix.AF.INET) {
            const in_addr: *const posix.sockaddr.in = @ptrCast(&self.addr);
            return std.mem.bigToNative(u16, in_addr.port);
        } else if (self.addr.family == posix.AF.INET6) {
            const in6_addr: *const posix.sockaddr.in6 = @ptrCast(&self.addr);
            return std.mem.bigToNative(u16, in6_addr.port);
        }
        return 0;
    }

    /// Get IP as string
    pub fn getIpString(self: *const Address, buffer: []u8) ![]u8 {
        if (self.addr.family == posix.AF.INET) {
            const in_addr: *const posix.sockaddr.in = @ptrCast(&self.addr);
            const bytes = std.mem.asBytes(&in_addr.addr);
            return std.fmt.bufPrint(buffer, "{}.{}.{}.{}", .{
                bytes[0],
                bytes[1],
                bytes[2],
                bytes[3],
            }) catch return error.BufferTooSmall;
        }
        return error.UnsupportedFamily;
    }
};

fn parseIpv4(ip: []const u8) !u32 {
    var result: u32 = 0;
    var octet: u8 = 0;
    var octet_count: u8 = 0;
    var shift: u5 = 24;

    for (ip) |c| {
        if (c == '.') {
            result |= @as(u32, octet) << shift;
            if (shift == 0) return error.InvalidAddress;
            shift -= 8;
            octet = 0;
            octet_count += 1;
        } else if (c >= '0' and c <= '9') {
            octet = octet * 10 + (c - '0');
        } else {
            return error.InvalidAddress;
        }
    }
    result |= @as(u32, octet) << shift;

    if (octet_count != 3) return error.InvalidAddress;
    return result;
}

fn parseIpv6(ip: []const u8) ![16]u8 {
    _ = ip;
    // Simplified - just return zeros for now
    return [_]u8{0} ** 16;
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a socket (convenience function)
pub fn socket(family: i32, sock_type: i32, protocol: i32) !Socket {
    return Socket.init(family, sock_type, protocol);
}

/// Create a TCP socket pair
pub fn socketpair(family: i32, sock_type: i32, protocol: i32) !struct { a: Socket, b: Socket } {
    const fds = try posix.socketpair(
        @enumFromInt(family),
        @enumFromInt(sock_type),
        @enumFromInt(protocol),
    );
    return .{
        .a = Socket.fromHandle(fds[0], family, sock_type, protocol),
        .b = Socket.fromHandle(fds[1], family, sock_type, protocol),
    };
}

/// Create a connected socket pair
pub fn createConnection(allocator: std.mem.Allocator, host: []const u8, port: u16, timeout: ?f64) !Socket {
    _ = allocator;

    var sock = try Socket.init(AF_INET, SOCK_STREAM, 0);
    errdefer sock.close();

    if (timeout) |t| {
        try sock.settimeout(t);
    }

    const addr = try Address.inet4(host, port);
    try sock.connect(addr);

    return sock;
}

/// Get host name
pub fn gethostname(buffer: []u8) ![]u8 {
    // Use uname on Unix
    if (comptime builtin.os.tag != .windows) {
        var name = posix.uname();
        const len = std.mem.indexOfScalar(u8, &name.nodename, 0) orelse name.nodename.len;
        const copy_len = @min(len, buffer.len);
        @memcpy(buffer[0..copy_len], name.nodename[0..copy_len]);
        return buffer[0..copy_len];
    }
    return error.NotImplemented;
}

/// Get fully qualified domain name
pub fn getfqdn(allocator: std.mem.Allocator, name: ?[]const u8) ![]u8 {
    if (name) |n| {
        return try allocator.dupe(u8, n);
    }
    var buffer: [256]u8 = undefined;
    const hostname = try gethostname(&buffer);
    return try allocator.dupe(u8, hostname);
}

/// Convert host byte order to network byte order (16-bit)
pub fn htons(hostshort: u16) u16 {
    return std.mem.nativeToBig(u16, hostshort);
}

/// Convert network byte order to host byte order (16-bit)
pub fn ntohs(netshort: u16) u16 {
    return std.mem.bigToNative(u16, netshort);
}

/// Convert host byte order to network byte order (32-bit)
pub fn htonl(hostlong: u32) u32 {
    return std.mem.nativeToBig(u32, hostlong);
}

/// Convert network byte order to host byte order (32-bit)
pub fn ntohl(netlong: u32) u32 {
    return std.mem.bigToNative(u32, netlong);
}

/// Convert IPv4 address to packed binary
pub fn inet_aton(ip: []const u8) !u32 {
    return parseIpv4(ip);
}

/// Convert packed binary to IPv4 address string
pub fn inet_ntoa(packed: u32, buffer: []u8) ![]u8 {
    const bytes = std.mem.asBytes(&packed);
    return std.fmt.bufPrint(buffer, "{}.{}.{}.{}", .{
        bytes[3],
        bytes[2],
        bytes[1],
        bytes[0],
    }) catch return error.BufferTooSmall;
}

/// Get address info (simplified)
pub fn getaddrinfo(allocator: std.mem.Allocator, host: []const u8, port: u16) ![]Address {
    _ = allocator;

    // Simplified - just return a single IPv4 address
    var result: [1]Address = undefined;
    result[0] = try Address.inet4(host, port);
    return &result;
}

/// Check if socket has pending data using poll()
pub fn hasData(sock: *Socket) bool {
    if (sock.fd < 0) return false;

    var fds = [1]posix.pollfd{
        .{
            .fd = sock.fd,
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
    if (sock.fd < 0) return error.InvalidSocket;

    const current_flags = posix.fcntl(sock.fd, posix.F.GETFD, 0) catch |err| {
        return switch (err) {
            error.FileDescriptorInvalid => error.InvalidSocket,
            else => error.FcntlFailed,
        };
    };

    const new_flags = if (inheritable)
        current_flags & ~@as(i32, posix.FD_CLOEXEC)
    else
        current_flags | posix.FD_CLOEXEC;

    _ = posix.fcntl(sock.fd, posix.F.SETFD, new_flags) catch {
        return error.FcntlFailed;
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Socket create and close" {
    var sock = try Socket.init(AF_INET, SOCK_STREAM, 0);
    sock.close();
}

test "Address inet4" {
    const addr = try Address.inet4("127.0.0.1", 8080);
    try std.testing.expectEqual(@as(u16, 8080), addr.getPort());
}

test "htons/ntohs" {
    const val: u16 = 0x1234;
    const net = htons(val);
    const host = ntohs(net);
    try std.testing.expectEqual(val, host);
}

test "htonl/ntohl" {
    const val: u32 = 0x12345678;
    const net = htonl(val);
    const host = ntohl(net);
    try std.testing.expectEqual(val, host);
}

test "inet_aton" {
    const packed = try inet_aton("192.168.1.1");
    try std.testing.expect(packed != 0);
}

test "constants" {
    try std.testing.expectEqual(@as(i32, 2), AF_INET);
    try std.testing.expectEqual(@as(i32, 1), SOCK_STREAM);
    try std.testing.expectEqual(@as(i32, 6), IPPROTO_TCP);
}

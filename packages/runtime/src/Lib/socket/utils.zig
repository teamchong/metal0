//! Socket utility functions
//!
//! Provides convenience functions for socket operations including
//! socket creation, DNS resolution, hostname retrieval, and address info.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const net = std.net;
const allocator_helper = @import("utils.allocator_helper");

const constants = @import("constants.zig");
const socket_class = @import("socket_class.zig");
const address_mod = @import("address.zig");

pub const Socket = socket_class.Socket;
pub const Address = address_mod.Address;

// ============================================================================
// Socket Creation Functions
// ============================================================================

/// Create a socket (convenience function)
pub fn socket(family: i32, sock_type: i32, protocol: i32) !Socket {
    return Socket.init(family, sock_type, protocol);
}

/// Create a TCP socket pair
pub fn socketpair(family: i32, sock_type: i32, protocol: i32) !struct { a: Socket, b: Socket } {
    const fds = try posix.socketpair(
        @intCast(family),
        @intCast(sock_type),
        @intCast(protocol),
    );
    return .{
        .a = Socket.fromHandle(fds[0], family, sock_type, protocol),
        .b = Socket.fromHandle(fds[1], family, sock_type, protocol),
    };
}

/// Create a connected socket pair
pub fn createConnection(allocator: std.mem.Allocator, host: []const u8, port: u16, timeout: ?f64) !Socket {
    _ = allocator;

    var sock = try Socket.init(constants.AF_INET, constants.SOCK_STREAM, 0);
    errdefer sock.close();

    if (timeout) |t| {
        try sock.settimeout(t);
    }

    const addr = try Address.inet4(host, port);
    try sock.connect(addr);

    return sock;
}

// ============================================================================
// Hostname and DNS Functions
// ============================================================================

/// Get host name
pub fn gethostname(buffer: []u8) ![]u8 {
    if (comptime builtin.os.tag == .windows) {
        // Windows: use GetComputerNameExA
        const kernel32 = @cImport(@cInclude("windows.h"));
        var size: u32 = @intCast(buffer.len);
        if (kernel32.GetComputerNameExA(kernel32.ComputerNameDnsHostname, buffer.ptr, &size) != 0) {
            return buffer[0..size];
        }
        // Fallback: use environment variable
        if (std.process.getEnvVarOwned(allocator_helper.fast_allocator, "COMPUTERNAME")) |name| {
            defer allocator_helper.fast_allocator.free(name);
            const copy_len = @min(name.len, buffer.len);
            @memcpy(buffer[0..copy_len], name[0..copy_len]);
            return buffer[0..copy_len];
        } else |_| {}
        return error.HostUnreachable;
    } else {
        // Unix: use uname
        var name = posix.uname();
        const len = std.mem.indexOfScalar(u8, &name.nodename, 0) orelse name.nodename.len;
        const copy_len = @min(len, buffer.len);
        @memcpy(buffer[0..copy_len], name.nodename[0..copy_len]);
        return buffer[0..copy_len];
    }
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

/// Get address info (simplified)
pub fn getaddrinfo(allocator: std.mem.Allocator, host: []const u8, port: u16) ![]Address {
    // Try to parse as IP address directly
    const single = allocator.alloc(Address, 1) catch return error.OutOfMemory;
    single[0] = Address.inet4(host, port) catch {
        // If parsing fails, return error
        allocator.free(single);
        return error.InvalidAddress;
    };
    return single;
}

//! Socket address handling
//!
//! Provides the Address struct for working with IPv4/IPv6 addresses,
//! along with parsing and formatting utilities.

const std = @import("std");
const posix = std.posix;
const constants = @import("constants.zig");

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
            const in_addr: *const posix.sockaddr.in = @ptrCast(@alignCast(&self.addr));
            return std.mem.bigToNative(u16, in_addr.port);
        } else if (self.addr.family == posix.AF.INET6) {
            const in6_addr: *const posix.sockaddr.in6 = @ptrCast(@alignCast(&self.addr));
            return std.mem.bigToNative(u16, in6_addr.port);
        }
        return 0;
    }

    /// Get IP as string
    pub fn getIpString(self: *const Address, buffer: []u8) ![]u8 {
        if (self.addr.family == posix.AF.INET) {
            const in_addr: *const posix.sockaddr.in = @ptrCast(@alignCast(&self.addr));
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

// ============================================================================
// IP Parsing Functions
// ============================================================================

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
    var result: [16]u8 = [_]u8{0} ** 16;

    // Handle :: (all zeros)
    if (std.mem.eql(u8, ip, "::")) {
        return result;
    }

    // Handle ::1 (loopback)
    if (std.mem.eql(u8, ip, "::1")) {
        result[15] = 1;
        return result;
    }

    // Find :: position for compression
    var double_colon_pos: ?usize = null;
    if (std.mem.indexOf(u8, ip, "::")) |pos| {
        double_colon_pos = pos;
    }

    var write_idx: usize = 0;
    var iter = std.mem.splitScalar(u8, ip, ':');

    while (iter.next()) |segment| {
        if (segment.len == 0) {
            // Part of :: compression
            if (double_colon_pos != null and write_idx < 16) {
                // Calculate how many zeros to insert
                // Count remaining non-empty segments
                var remaining: usize = 0;
                var temp_iter = iter;
                while (temp_iter.next()) |s| {
                    if (s.len > 0) remaining += 1;
                }
                const zeros_needed = 16 - write_idx - (remaining * 2);
                write_idx += zeros_needed;
            }
            continue;
        }

        if (segment.len > 4 or write_idx >= 15) return error.InvalidAddress;

        // Parse hex value
        const val = std.fmt.parseInt(u16, segment, 16) catch return error.InvalidAddress;
        result[write_idx] = @intCast((val >> 8) & 0xFF);
        result[write_idx + 1] = @intCast(val & 0xFF);
        write_idx += 2;
    }

    return result;
}

// ============================================================================
// Conversion Functions
// ============================================================================

/// Convert IPv4 address to packed binary
pub fn inet_aton(ip: []const u8) !u32 {
    return parseIpv4(ip);
}

/// Convert packed binary to IPv4 address string
pub fn inet_ntoa(buffer: []u8, packed_ip: u32) ![]u8 {
    const bytes = std.mem.asBytes(&packed_ip);
    return std.fmt.bufPrint(buffer, "{}.{}.{}.{}", .{
        bytes[3],
        bytes[2],
        bytes[1],
        bytes[0],
    }) catch return error.BufferTooSmall;
}

// ============================================================================
// Byte Order Conversion
// ============================================================================

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

// ============================================================================
// Tests
// ============================================================================

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
    const packed_ip = try inet_aton("192.168.1.1");
    try std.testing.expect(packed_ip != 0);
}

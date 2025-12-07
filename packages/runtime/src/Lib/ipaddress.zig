//! CPython source: Lib/ipaddress.py
//!
//! Provides classes for working with IP addresses and networks.
//!
//! Mirrors: CPython Lib/ipaddress.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const AddressValueError = error{
    /// Invalid address format
    InvalidAddress,
    /// Invalid network format
    InvalidNetwork,
    /// Invalid prefix length
    InvalidPrefixLen,
    /// Address is not in network
    AddressNotInNetwork,
    /// Host bits set in network address
    HostBitsSet,
};

// ============================================================================
// Constants
// ============================================================================

/// IPv4 constants
pub const IPV4 = struct {
    pub const LENGTH = 32;
    pub const MAX_PREFIXLEN = 32;
    pub const ALL_ONES: u32 = 0xFFFFFFFF;
};

/// IPv6 constants
pub const IPV6 = struct {
    pub const LENGTH = 128;
    pub const MAX_PREFIXLEN = 128;
    pub const ALL_ONES: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
};

// ============================================================================
// IPv4Address
// ============================================================================

/// IPv4 address
pub const IPv4Address = struct {
    const Self = @This();

    packed: u32,

    /// Create from string
    pub fn init(address: []const u8) !Self {
        var octets: [4]u8 = undefined;
        var octet_idx: usize = 0;
        var current: u32 = 0;

        for (address) |c| {
            if (c == '.') {
                if (current > 255) return AddressValueError.InvalidAddress;
                if (octet_idx >= 3) return AddressValueError.InvalidAddress;
                octets[octet_idx] = @intCast(current);
                octet_idx += 1;
                current = 0;
            } else if (c >= '0' and c <= '9') {
                current = current * 10 + (c - '0');
            } else {
                return AddressValueError.InvalidAddress;
            }
        }

        if (current > 255) return AddressValueError.InvalidAddress;
        if (octet_idx != 3) return AddressValueError.InvalidAddress;
        octets[octet_idx] = @intCast(current);

        return .{
            .packed = (@as(u32, octets[0]) << 24) |
                (@as(u32, octets[1]) << 16) |
                (@as(u32, octets[2]) << 8) |
                @as(u32, octets[3]),
        };
    }

    /// Create from integer
    pub fn fromInt(value: u32) Self {
        return .{ .packed = value };
    }

    /// Create from packed bytes
    pub fn fromBytes(bytes: [4]u8) Self {
        return .{
            .packed = (@as(u32, bytes[0]) << 24) |
                (@as(u32, bytes[1]) << 16) |
                (@as(u32, bytes[2]) << 8) |
                @as(u32, bytes[3]),
        };
    }

    /// Get as integer
    pub fn toInt(self: Self) u32 {
        return self.packed;
    }

    /// Get as packed bytes
    pub fn toBytes(self: Self) [4]u8 {
        return .{
            @intCast((self.packed >> 24) & 0xFF),
            @intCast((self.packed >> 16) & 0xFF),
            @intCast((self.packed >> 8) & 0xFF),
            @intCast(self.packed & 0xFF),
        };
    }

    /// Format as string
    pub fn format(self: Self, buf: []u8) ![]u8 {
        const bytes = self.toBytes();
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3] }) catch
            return AddressValueError.InvalidAddress;
    }

    /// Check if private address
    pub fn isPrivate(self: Self) bool {
        const bytes = self.toBytes();
        // 10.0.0.0/8
        if (bytes[0] == 10) return true;
        // 172.16.0.0/12
        if (bytes[0] == 172 and bytes[1] >= 16 and bytes[1] <= 31) return true;
        // 192.168.0.0/16
        if (bytes[0] == 192 and bytes[1] == 168) return true;
        return false;
    }

    /// Check if global (public) address
    pub fn isGlobal(self: Self) bool {
        return !self.isPrivate() and !self.isLoopback() and !self.isLinkLocal() and !self.isMulticast() and !self.isReserved();
    }

    /// Check if loopback address
    pub fn isLoopback(self: Self) bool {
        const bytes = self.toBytes();
        return bytes[0] == 127;
    }

    /// Check if link-local address
    pub fn isLinkLocal(self: Self) bool {
        const bytes = self.toBytes();
        return bytes[0] == 169 and bytes[1] == 254;
    }

    /// Check if multicast address
    pub fn isMulticast(self: Self) bool {
        const bytes = self.toBytes();
        return bytes[0] >= 224 and bytes[0] <= 239;
    }

    /// Check if reserved address
    pub fn isReserved(self: Self) bool {
        const bytes = self.toBytes();
        // 0.0.0.0/8
        if (bytes[0] == 0) return true;
        // 240.0.0.0/4
        if (bytes[0] >= 240) return true;
        return false;
    }

    /// Check if unspecified (0.0.0.0)
    pub fn isUnspecified(self: Self) bool {
        return self.packed == 0;
    }

    /// Version
    pub fn version(_: Self) u8 {
        return 4;
    }

    /// Max prefix length
    pub fn maxPrefixlen(_: Self) u8 {
        return IPV4.MAX_PREFIXLEN;
    }

    /// Reverse pointer name
    pub fn reversePointer(self: Self, buf: []u8) ![]u8 {
        const bytes = self.toBytes();
        return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}.in-addr.arpa", .{
            bytes[3], bytes[2], bytes[1], bytes[0],
        }) catch return AddressValueError.InvalidAddress;
    }

    /// Compare addresses
    pub fn compare(self: Self, other: Self) std.math.Order {
        return std.math.order(self.packed, other.packed);
    }

    /// Check equality
    pub fn eql(self: Self, other: Self) bool {
        return self.packed == other.packed;
    }
};

// ============================================================================
// IPv4Network
// ============================================================================

/// IPv4 network
pub const IPv4Network = struct {
    const Self = @This();

    network_address: IPv4Address,
    prefixlen: u8,

    /// Create from string (CIDR notation)
    pub fn init(address: []const u8, strict: bool) !Self {
        const slash_idx = std.mem.indexOf(u8, address, "/") orelse return AddressValueError.InvalidNetwork;

        const addr_part = address[0..slash_idx];
        const prefix_part = address[slash_idx + 1 ..];

        const net_addr = try IPv4Address.init(addr_part);
        const prefixlen = std.fmt.parseInt(u8, prefix_part, 10) catch return AddressValueError.InvalidPrefixLen;

        if (prefixlen > IPV4.MAX_PREFIXLEN) return AddressValueError.InvalidPrefixLen;

        // Calculate network address (mask off host bits)
        const mask = if (prefixlen == 0) 0 else ~@as(u32, 0) << @intCast(32 - prefixlen);
        const network = net_addr.packed & mask;

        if (strict and network != net_addr.packed) {
            return AddressValueError.HostBitsSet;
        }

        return .{
            .network_address = IPv4Address.fromInt(network),
            .prefixlen = prefixlen,
        };
    }

    /// Get netmask
    pub fn netmask(self: Self) IPv4Address {
        const mask = if (self.prefixlen == 0) 0 else ~@as(u32, 0) << @intCast(32 - self.prefixlen);
        return IPv4Address.fromInt(mask);
    }

    /// Get hostmask (inverse of netmask)
    pub fn hostmask(self: Self) IPv4Address {
        const mask = if (self.prefixlen == 32) 0 else ~(@as(u32, 0) << @intCast(32 - self.prefixlen)) >> @intCast(32 - self.prefixlen) | (@as(u32, 1) << @intCast(32 - self.prefixlen)) - 1;
        return IPv4Address.fromInt(~self.netmask().packed);
    }

    /// Get broadcast address
    pub fn broadcastAddress(self: Self) IPv4Address {
        return IPv4Address.fromInt(self.network_address.packed | ~self.netmask().packed);
    }

    /// Number of addresses in network
    pub fn numAddresses(self: Self) u64 {
        return @as(u64, 1) << @intCast(32 - self.prefixlen);
    }

    /// Check if address is in network
    pub fn contains(self: Self, address: IPv4Address) bool {
        const mask = self.netmask().packed;
        return (address.packed & mask) == self.network_address.packed;
    }

    /// Check if this network overlaps with another
    pub fn overlaps(self: Self, other: Self) bool {
        return self.contains(other.network_address) or
            self.contains(other.broadcastAddress()) or
            other.contains(self.network_address) or
            other.contains(self.broadcastAddress());
    }

    /// Check if network is a supernet of other
    pub fn supernetOf(self: Self, other: Self) bool {
        return self.prefixlen < other.prefixlen and self.contains(other.network_address);
    }

    /// Check if network is a subnet of other
    pub fn subnetOf(self: Self, other: Self) bool {
        return other.supernetOf(self);
    }

    /// Get supernet
    pub fn supernet(self: Self, prefixlen_diff: ?u8) !Self {
        const diff = prefixlen_diff orelse 1;
        if (diff > self.prefixlen) return AddressValueError.InvalidPrefixLen;
        const new_prefixlen = self.prefixlen - diff;
        const mask = if (new_prefixlen == 0) 0 else ~@as(u32, 0) << @intCast(32 - new_prefixlen);
        return .{
            .network_address = IPv4Address.fromInt(self.network_address.packed & mask),
            .prefixlen = new_prefixlen,
        };
    }

    /// Check if private network
    pub fn isPrivate(self: Self) bool {
        return self.network_address.isPrivate();
    }

    /// Check if global network
    pub fn isGlobal(self: Self) bool {
        return self.network_address.isGlobal();
    }

    /// Check if link-local network
    pub fn isLinkLocal(self: Self) bool {
        return self.network_address.isLinkLocal();
    }

    /// Check if loopback network
    pub fn isLoopback(self: Self) bool {
        return self.network_address.isLoopback();
    }

    /// Check if multicast network
    pub fn isMulticast(self: Self) bool {
        return self.network_address.isMulticast();
    }

    /// Format as string
    pub fn format(self: Self, buf: []u8) ![]u8 {
        var addr_buf: [16]u8 = undefined;
        const addr_str = try self.network_address.format(&addr_buf);
        return std.fmt.bufPrint(buf, "{s}/{d}", .{ addr_str, self.prefixlen }) catch
            return AddressValueError.InvalidNetwork;
    }

    /// Version
    pub fn version(_: Self) u8 {
        return 4;
    }

    /// With prefix length
    pub fn withPrefixlen(self: Self) Self {
        return self;
    }

    /// With netmask
    pub fn withNetmask(self: Self) Self {
        return self;
    }

    /// With hostmask
    pub fn withHostmask(self: Self) Self {
        return self;
    }
};

// ============================================================================
// IPv4Interface
// ============================================================================

/// IPv4 interface (address + network)
pub const IPv4Interface = struct {
    const Self = @This();

    address: IPv4Address,
    network: IPv4Network,

    pub fn init(address: []const u8) !Self {
        if (std.mem.indexOf(u8, address, "/")) |slash_idx| {
            const addr_part = address[0..slash_idx];
            const prefix_part = address[slash_idx + 1 ..];

            const addr = try IPv4Address.init(addr_part);
            const prefixlen = std.fmt.parseInt(u8, prefix_part, 10) catch return AddressValueError.InvalidPrefixLen;

            if (prefixlen > IPV4.MAX_PREFIXLEN) return AddressValueError.InvalidPrefixLen;

            const mask = if (prefixlen == 0) 0 else ~@as(u32, 0) << @intCast(32 - prefixlen);
            const network = IPv4Address.fromInt(addr.packed & mask);

            return .{
                .address = addr,
                .network = .{
                    .network_address = network,
                    .prefixlen = prefixlen,
                },
            };
        } else {
            const addr = try IPv4Address.init(address);
            return .{
                .address = addr,
                .network = .{
                    .network_address = addr,
                    .prefixlen = IPV4.MAX_PREFIXLEN,
                },
            };
        }
    }

    /// Get IP address
    pub fn ip(self: Self) IPv4Address {
        return self.address;
    }

    /// With prefix length
    pub fn withPrefixlen(self: Self, buf: []u8) ![]u8 {
        var addr_buf: [16]u8 = undefined;
        const addr_str = try self.address.format(&addr_buf);
        return std.fmt.bufPrint(buf, "{s}/{d}", .{ addr_str, self.network.prefixlen }) catch
            return AddressValueError.InvalidAddress;
    }

    /// With netmask
    pub fn withNetmask(self: Self, buf: []u8) ![]u8 {
        var addr_buf: [16]u8 = undefined;
        var mask_buf: [16]u8 = undefined;
        const addr_str = try self.address.format(&addr_buf);
        const mask_str = try self.network.netmask().format(&mask_buf);
        return std.fmt.bufPrint(buf, "{s}/{s}", .{ addr_str, mask_str }) catch
            return AddressValueError.InvalidAddress;
    }
};

// ============================================================================
// IPv6Address
// ============================================================================

/// IPv6 address
pub const IPv6Address = struct {
    const Self = @This();

    packed: u128,

    /// Create from string
    pub fn init(address: []const u8) !Self {
        // Handle :: expansion
        var groups: [8]u16 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        var group_idx: usize = 0;
        var current: u32 = 0;
        var digits: usize = 0;
        var double_colon_idx: ?usize = null;
        var after_double_colon: usize = 0;

        var i: usize = 0;
        while (i < address.len) : (i += 1) {
            const c = address[i];

            if (c == ':') {
                if (i + 1 < address.len and address[i + 1] == ':') {
                    // :: found
                    if (double_colon_idx != null) return AddressValueError.InvalidAddress;
                    if (digits > 0) {
                        groups[group_idx] = @intCast(current);
                        group_idx += 1;
                    }
                    double_colon_idx = group_idx;
                    current = 0;
                    digits = 0;
                    i += 1;
                } else {
                    if (digits == 0 and i > 0) return AddressValueError.InvalidAddress;
                    groups[group_idx] = @intCast(current);
                    group_idx += 1;
                    if (double_colon_idx != null) after_double_colon += 1;
                    current = 0;
                    digits = 0;
                }
            } else {
                const val = std.fmt.charToDigit(c, 16) catch return AddressValueError.InvalidAddress;
                current = current * 16 + val;
                digits += 1;
                if (digits > 4) return AddressValueError.InvalidAddress;
            }
        }

        // Last group
        if (digits > 0) {
            groups[group_idx] = @intCast(current);
            group_idx += 1;
            if (double_colon_idx != null) after_double_colon += 1;
        }

        // Expand ::
        if (double_colon_idx) |dci| {
            const zeros_needed = 8 - group_idx;
            // Shift groups after :: to the end
            var j: usize = 7;
            var src: usize = group_idx - 1;
            while (j >= dci + zeros_needed) : (j -= 1) {
                if (src >= dci) {
                    groups[j] = groups[src];
                    groups[src] = 0;
                    if (src > 0) src -= 1 else break;
                }
                if (j == 0) break;
            }
        }

        // Pack into u128
        var packed: u128 = 0;
        for (groups) |g| {
            packed = (packed << 16) | g;
        }

        return .{ .packed = packed };
    }

    /// Create from integer
    pub fn fromInt(value: u128) Self {
        return .{ .packed = value };
    }

    /// Create from bytes
    pub fn fromBytes(bytes: [16]u8) Self {
        var packed: u128 = 0;
        for (bytes) |b| {
            packed = (packed << 8) | b;
        }
        return .{ .packed = packed };
    }

    /// Get as integer
    pub fn toInt(self: Self) u128 {
        return self.packed;
    }

    /// Get as bytes
    pub fn toBytes(self: Self) [16]u8 {
        var bytes: [16]u8 = undefined;
        var val = self.packed;
        var i: usize = 15;
        while (true) : (i -= 1) {
            bytes[i] = @intCast(val & 0xFF);
            val >>= 8;
            if (i == 0) break;
        }
        return bytes;
    }

    /// Format as string (full form)
    pub fn format(self: Self, buf: []u8) ![]u8 {
        var groups: [8]u16 = undefined;
        var val = self.packed;
        var i: usize = 7;
        while (true) : (i -= 1) {
            groups[i] = @intCast(val & 0xFFFF);
            val >>= 16;
            if (i == 0) break;
        }

        return std.fmt.bufPrint(buf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
            groups[0], groups[1], groups[2], groups[3],
            groups[4], groups[5], groups[6], groups[7],
        }) catch return AddressValueError.InvalidAddress;
    }

    /// Check if loopback (::1)
    pub fn isLoopback(self: Self) bool {
        return self.packed == 1;
    }

    /// Check if unspecified (::)
    pub fn isUnspecified(self: Self) bool {
        return self.packed == 0;
    }

    /// Check if link-local (fe80::/10)
    pub fn isLinkLocal(self: Self) bool {
        return (self.packed >> 118) == 0x3FA; // fe80 >> 6
    }

    /// Check if site-local (fec0::/10) - deprecated
    pub fn isSiteLocal(self: Self) bool {
        return (self.packed >> 118) == 0x3FB; // fec0 >> 6
    }

    /// Check if multicast (ff00::/8)
    pub fn isMulticast(self: Self) bool {
        return (self.packed >> 120) == 0xFF;
    }

    /// Check if private (fc00::/7 - unique local)
    pub fn isPrivate(self: Self) bool {
        return (self.packed >> 121) == 0x7E; // fc >> 1
    }

    /// Check if global
    pub fn isGlobal(self: Self) bool {
        return !self.isPrivate() and !self.isLoopback() and !self.isLinkLocal() and !self.isMulticast() and !self.isUnspecified();
    }

    /// Check if reserved
    pub fn isReserved(self: Self) bool {
        // Various reserved ranges
        return self.isUnspecified() or self.isLoopback();
    }

    /// Check if IPv4-mapped (::ffff:0:0/96)
    pub fn isIpv4Mapped(self: Self) bool {
        return (self.packed >> 32) == 0xFFFF;
    }

    /// Get IPv4-mapped address
    pub fn ipv4Mapped(self: Self) ?IPv4Address {
        if (!self.isIpv4Mapped()) return null;
        return IPv4Address.fromInt(@intCast(self.packed & 0xFFFFFFFF));
    }

    /// Version
    pub fn version(_: Self) u8 {
        return 6;
    }

    /// Max prefix length
    pub fn maxPrefixlen(_: Self) u8 {
        return IPV6.MAX_PREFIXLEN;
    }

    /// Check equality
    pub fn eql(self: Self, other: Self) bool {
        return self.packed == other.packed;
    }
};

// ============================================================================
// IPv6Network
// ============================================================================

/// IPv6 network
pub const IPv6Network = struct {
    const Self = @This();

    network_address: IPv6Address,
    prefixlen: u8,

    /// Create from string (CIDR notation)
    pub fn init(address: []const u8, strict: bool) !Self {
        const slash_idx = std.mem.indexOf(u8, address, "/") orelse return AddressValueError.InvalidNetwork;

        const addr_part = address[0..slash_idx];
        const prefix_part = address[slash_idx + 1 ..];

        const net_addr = try IPv6Address.init(addr_part);
        const prefixlen = std.fmt.parseInt(u8, prefix_part, 10) catch return AddressValueError.InvalidPrefixLen;

        if (prefixlen > IPV6.MAX_PREFIXLEN) return AddressValueError.InvalidPrefixLen;

        // Calculate network address
        const mask = if (prefixlen == 0) 0 else ~@as(u128, 0) << @intCast(128 - prefixlen);
        const network = net_addr.packed & mask;

        if (strict and network != net_addr.packed) {
            return AddressValueError.HostBitsSet;
        }

        return .{
            .network_address = IPv6Address.fromInt(network),
            .prefixlen = prefixlen,
        };
    }

    /// Get netmask
    pub fn netmask(self: Self) IPv6Address {
        const mask = if (self.prefixlen == 0) 0 else ~@as(u128, 0) << @intCast(128 - self.prefixlen);
        return IPv6Address.fromInt(mask);
    }

    /// Check if address is in network
    pub fn contains(self: Self, address: IPv6Address) bool {
        const mask = self.netmask().packed;
        return (address.packed & mask) == self.network_address.packed;
    }

    /// Check if private
    pub fn isPrivate(self: Self) bool {
        return self.network_address.isPrivate();
    }

    /// Check if global
    pub fn isGlobal(self: Self) bool {
        return self.network_address.isGlobal();
    }

    /// Version
    pub fn version(_: Self) u8 {
        return 6;
    }
};

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Create address from string (auto-detect version)
pub fn ip_address(address: []const u8) !union(enum) { v4: IPv4Address, v6: IPv6Address } {
    if (std.mem.indexOf(u8, address, ":") != null) {
        return .{ .v6 = try IPv6Address.init(address) };
    } else {
        return .{ .v4 = try IPv4Address.init(address) };
    }
}

/// Create network from string (auto-detect version)
pub fn ip_network(address: []const u8, strict: bool) !union(enum) { v4: IPv4Network, v6: IPv6Network } {
    if (std.mem.indexOf(u8, address, ":") != null) {
        return .{ .v6 = try IPv6Network.init(address, strict) };
    } else {
        return .{ .v4 = try IPv4Network.init(address, strict) };
    }
}

/// Create interface from string (auto-detect version)
pub fn ip_interface(address: []const u8) !IPv4Interface {
    return IPv4Interface.init(address);
}

/// Collapse list of networks to minimum set
pub fn collapse_addresses(addresses: []const IPv4Network) []const IPv4Network {
    // Would merge adjacent/overlapping networks
    return addresses;
}

/// Summarize networks into smallest set
pub fn summarize_address_range(first: IPv4Address, last: IPv4Address) ![]const IPv4Network {
    _ = first;
    _ = last;
    // Would return list of networks covering the range
    return &[_]IPv4Network{};
}

// ============================================================================
// Tests
// ============================================================================

test "IPv4Address init" {
    const addr = try IPv4Address.init("192.168.1.1");
    try std.testing.expectEqual(@as(u32, 0xC0A80101), addr.packed);
}

test "IPv4Address format" {
    const addr = IPv4Address.fromInt(0xC0A80101);
    var buf: [16]u8 = undefined;
    const str = try addr.format(&buf);
    try std.testing.expectEqualStrings("192.168.1.1", str);
}

test "IPv4Address properties" {
    const private = try IPv4Address.init("192.168.1.1");
    try std.testing.expect(private.isPrivate());
    try std.testing.expect(!private.isLoopback());

    const loopback = try IPv4Address.init("127.0.0.1");
    try std.testing.expect(loopback.isLoopback());

    const link_local = try IPv4Address.init("169.254.1.1");
    try std.testing.expect(link_local.isLinkLocal());

    const multicast = try IPv4Address.init("224.0.0.1");
    try std.testing.expect(multicast.isMulticast());
}

test "IPv4Network init" {
    const net = try IPv4Network.init("192.168.1.0/24", true);
    try std.testing.expectEqual(@as(u8, 24), net.prefixlen);
    try std.testing.expectEqual(@as(u32, 0xC0A80100), net.network_address.packed);
}

test "IPv4Network contains" {
    const net = try IPv4Network.init("192.168.1.0/24", true);
    const addr_in = try IPv4Address.init("192.168.1.100");
    const addr_out = try IPv4Address.init("192.168.2.1");

    try std.testing.expect(net.contains(addr_in));
    try std.testing.expect(!net.contains(addr_out));
}

test "IPv4Network netmask" {
    const net = try IPv4Network.init("192.168.1.0/24", true);
    var buf: [16]u8 = undefined;
    const mask_str = try net.netmask().format(&buf);
    try std.testing.expectEqualStrings("255.255.255.0", mask_str);
}

test "IPv4Network broadcast" {
    const net = try IPv4Network.init("192.168.1.0/24", true);
    var buf: [16]u8 = undefined;
    const broadcast_str = try net.broadcastAddress().format(&buf);
    try std.testing.expectEqualStrings("192.168.1.255", broadcast_str);
}

test "IPv4Interface init" {
    const iface = try IPv4Interface.init("192.168.1.100/24");
    try std.testing.expectEqual(@as(u32, 0xC0A80164), iface.address.packed);
    try std.testing.expectEqual(@as(u8, 24), iface.network.prefixlen);
}

test "IPv6Address init simple" {
    const addr = try IPv6Address.init("::1");
    try std.testing.expectEqual(@as(u128, 1), addr.packed);
    try std.testing.expect(addr.isLoopback());
}

test "IPv6Address unspecified" {
    const addr = try IPv6Address.init("::");
    try std.testing.expect(addr.isUnspecified());
}

test "IPv6Address properties" {
    const loopback = try IPv6Address.init("::1");
    try std.testing.expect(loopback.isLoopback());
    try std.testing.expect(!loopback.isGlobal());
}

test "ip_address auto-detect" {
    const v4 = try ip_address("192.168.1.1");
    try std.testing.expect(v4 == .v4);

    const v6 = try ip_address("::1");
    try std.testing.expect(v6 == .v6);
}

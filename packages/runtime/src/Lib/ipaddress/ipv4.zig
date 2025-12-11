//! IPv4 address, network, and interface types
//!
//! CPython source: Lib/ipaddress.py

const std = @import("std");
const constants = @import("constants.zig");
const errors = @import("errors.zig");

const IPV4 = constants.IPV4;
const AddressValueError = errors.AddressValueError;

// ============================================================================
// IPv4Address
// ============================================================================

/// IPv4 address
pub const IPv4Address = struct {
    const Self = @This();

    _packed: u32,

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
            ._packed = (@as(u32, octets[0]) << 24) |
                (@as(u32, octets[1]) << 16) |
                (@as(u32, octets[2]) << 8) |
                @as(u32, octets[3]),
        };
    }

    /// Create from integer
    pub fn fromInt(value: u32) Self {
        return .{ ._packed = value };
    }

    /// Create from packed bytes
    pub fn fromBytes(bytes: [4]u8) Self {
        return .{
            ._packed = (@as(u32, bytes[0]) << 24) |
                (@as(u32, bytes[1]) << 16) |
                (@as(u32, bytes[2]) << 8) |
                @as(u32, bytes[3]),
        };
    }

    /// Get as integer
    pub fn toInt(self: Self) u32 {
        return self._packed;
    }

    /// Get as packed bytes
    pub fn toBytes(self: Self) [4]u8 {
        return .{
            @intCast((self._packed >> 24) & 0xFF),
            @intCast((self._packed >> 16) & 0xFF),
            @intCast((self._packed >> 8) & 0xFF),
            @intCast(self._packed & 0xFF),
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
        return self._packed == 0;
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
        return std.math.order(self._packed, other._packed);
    }

    /// Check equality
    pub fn eql(self: Self, other: Self) bool {
        return self._packed == other._packed;
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
        const network = net_addr._packed & mask;

        if (strict and network != net_addr._packed) {
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
        return IPv4Address.fromInt(~self.netmask()._packed);
    }

    /// Get broadcast address
    pub fn broadcastAddress(self: Self) IPv4Address {
        return IPv4Address.fromInt(self.network_address._packed | ~self.netmask()._packed);
    }

    /// Number of addresses in network
    pub fn numAddresses(self: Self) u64 {
        return @as(u64, 1) << @intCast(32 - self.prefixlen);
    }

    /// Check if address is in network
    pub fn contains(self: Self, address: IPv4Address) bool {
        const mask = self.netmask()._packed;
        return (address._packed & mask) == self.network_address._packed;
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
            .network_address = IPv4Address.fromInt(self.network_address._packed & mask),
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
            const network = IPv4Address.fromInt(addr._packed & mask);

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

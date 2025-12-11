//! IPv6 address, network, and interface types
//!
//! CPython source: Lib/ipaddress.py

const std = @import("std");
const constants = @import("constants.zig");
const errors = @import("errors.zig");
const ipv4 = @import("ipv4.zig");

const IPV6 = constants.IPV6;
const AddressValueError = errors.AddressValueError;
const IPv4Address = ipv4.IPv4Address;

// ============================================================================
// IPv6Address
// ============================================================================

/// IPv6 address
pub const IPv6Address = struct {
    const Self = @This();

    _packed: u128,

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
            if (group_idx > 0) {
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
        }

        // Pack into u128
        var result: u128 = 0;
        for (groups) |g| {
            result = (result << 16) | g;
        }

        return .{ ._packed = result };
    }

    /// Create from integer
    pub fn fromInt(value: u128) Self {
        return .{ ._packed = value };
    }

    /// Create from bytes
    pub fn fromBytes(bytes: [16]u8) Self {
        var result: u128 = 0;
        for (bytes) |b| {
            result = (result << 8) | b;
        }
        return .{ ._packed = result };
    }

    /// Get as integer
    pub fn toInt(self: Self) u128 {
        return self._packed;
    }

    /// Get as bytes
    pub fn toBytes(self: Self) [16]u8 {
        var bytes: [16]u8 = undefined;
        var val = self._packed;
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
        var val = self._packed;
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
        return self._packed == 1;
    }

    /// Check if unspecified (::)
    pub fn isUnspecified(self: Self) bool {
        return self._packed == 0;
    }

    /// Check if link-local (fe80::/10)
    pub fn isLinkLocal(self: Self) bool {
        return (self._packed >> 118) == 0x3FA; // fe80 >> 6
    }

    /// Check if site-local (fec0::/10) - deprecated
    pub fn isSiteLocal(self: Self) bool {
        return (self._packed >> 118) == 0x3FB; // fec0 >> 6
    }

    /// Check if multicast (ff00::/8)
    pub fn isMulticast(self: Self) bool {
        return (self._packed >> 120) == 0xFF;
    }

    /// Check if private (fc00::/7 - unique local)
    pub fn isPrivate(self: Self) bool {
        return (self._packed >> 121) == 0x7E; // fc >> 1
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
        return (self._packed >> 32) == 0xFFFF;
    }

    /// Get IPv4-mapped address
    pub fn ipv4Mapped(self: Self) ?IPv4Address {
        if (!self.isIpv4Mapped()) return null;
        return IPv4Address.fromInt(@intCast(self._packed & 0xFFFFFFFF));
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
        return self._packed == other._packed;
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
        const network = net_addr._packed & mask;

        if (strict and network != net_addr._packed) {
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
        const mask = self.netmask()._packed;
        return (address._packed & mask) == self.network_address._packed;
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
// IPv6Interface
// ============================================================================

/// IPv6 interface (address + network)
pub const IPv6Interface = struct {
    const Self = @This();

    address: IPv6Address,
    network: IPv6Network,

    pub fn init(address: []const u8) !Self {
        if (std.mem.indexOf(u8, address, "/")) |slash_idx| {
            const addr_part = address[0..slash_idx];
            const prefix_part = address[slash_idx + 1 ..];

            const addr = try IPv6Address.init(addr_part);
            const prefixlen = std.fmt.parseInt(u8, prefix_part, 10) catch return AddressValueError.InvalidPrefixLen;

            if (prefixlen > IPV6.MAX_PREFIXLEN) return AddressValueError.InvalidPrefixLen;

            const mask = if (prefixlen == 0) 0 else ~@as(u128, 0) << @intCast(128 - prefixlen);
            const network = IPv6Address.fromInt(addr._packed & mask);

            return .{
                .address = addr,
                .network = .{
                    .network_address = network,
                    .prefixlen = prefixlen,
                },
            };
        } else {
            const addr = try IPv6Address.init(address);
            return .{
                .address = addr,
                .network = .{
                    .network_address = addr,
                    .prefixlen = IPV6.MAX_PREFIXLEN,
                },
            };
        }
    }

    /// Get IP address
    pub fn ip(self: Self) IPv6Address {
        return self.address;
    }

    /// With prefix length
    pub fn withPrefixlen(self: Self, buf: []u8) ![]u8 {
        var addr_buf: [40]u8 = undefined;
        const addr_str = try self.address.format(&addr_buf);
        return std.fmt.bufPrint(buf, "{s}/{d}", .{ addr_str, self.network.prefixlen }) catch
            return AddressValueError.InvalidAddress;
    }

    /// With netmask
    pub fn withNetmask(self: Self, buf: []u8) ![]u8 {
        var addr_buf: [40]u8 = undefined;
        var mask_buf: [40]u8 = undefined;
        const addr_str = try self.address.format(&addr_buf);
        const mask_str = try self.network.netmask().format(&mask_buf);
        return std.fmt.bufPrint(buf, "{s}/{s}", .{ addr_str, mask_str }) catch
            return AddressValueError.InvalidAddress;
    }
};

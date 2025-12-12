//! Module-level utility functions for IP address handling
//!
//! CPython source: Lib/ipaddress.py

const std = @import("std");
const ipv4 = @import("ipv4.zig");
const ipv6 = @import("ipv6.zig");
const errors = @import("errors.zig");

const IPv4Address = ipv4.IPv4Address;
const IPv4Network = ipv4.IPv4Network;
const IPv4Interface = ipv4.IPv4Interface;
const IPv6Address = ipv6.IPv6Address;
const IPv6Network = ipv6.IPv6Network;
const AddressValueError = errors.AddressValueError;

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

/// Collapse list of networks to minimum set by merging adjacent/overlapping networks
pub fn collapse_addresses(allocator: std.mem.Allocator, addresses: []const IPv4Network) ![]IPv4Network {
    if (addresses.len == 0) return &[_]IPv4Network{};

    // Copy and sort by network address
    const sorted = try allocator.alloc(IPv4Network, addresses.len);
    @memcpy(sorted, addresses);

    // Sort by network address
    std.mem.sort(IPv4Network, sorted, {}, struct {
        fn lessThan(_: void, a: IPv4Network, b: IPv4Network) bool {
            return a.network_address._packed < b.network_address._packed;
        }
    }.lessThan);

    var result: std.ArrayList(IPv4Network) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < sorted.len) {
        var current = sorted[i];

        // Try to merge with following networks
        while (i + 1 < sorted.len) {
            const next = sorted[i + 1];

            // Check if current contains next
            const curr_broadcast = current.network_address._packed | ~current.netmask()._packed;
            if (next.network_address._packed <= curr_broadcast + 1) {
                // Networks overlap or are adjacent
                const next_broadcast = next.network_address._packed | ~next.netmask()._packed;
                if (next_broadcast > curr_broadcast) {
                    // Extend current to include next
                    const new_broadcast = next_broadcast;
                    // Find smallest prefix that covers both
                    var new_prefix: u8 = current.prefixlen;
                    while (new_prefix > 0) {
                        const mask = @as(u32, 0xFFFFFFFF) << @intCast(32 - new_prefix);
                        const start = current.network_address._packed & mask;
                        const end = start | ~mask;
                        if (start <= current.network_address._packed and end >= new_broadcast) {
                            current.network_address = IPv4Address.fromInt(start);
                            current.prefixlen = new_prefix;
                            break;
                        }
                        new_prefix -= 1;
                    }
                }
                i += 1;
            } else {
                break;
            }
        }

        try result.append(allocator, current);
        i += 1;
    }

    allocator.free(sorted);
    return result.toOwnedSlice(allocator);
}

/// Summarize networks into smallest set covering the address range
pub fn summarize_address_range(allocator: std.mem.Allocator, first: IPv4Address, last: IPv4Address) ![]IPv4Network {
    if (first._packed > last._packed) {
        return error.LastAddressBeforeFirst;
    }

    var networks: std.ArrayList(IPv4Network) = .{};
    errdefer networks.deinit(allocator);

    var ip = first._packed;
    const end = last._packed;

    while (ip <= end) {
        // Find the largest prefix that:
        // 1. Starts at ip
        // 2. Doesn't go past end
        var nbits: u8 = 32;

        while (nbits > 0) {
            // Check if this prefix length works
            const mask = if (nbits == 0) 0 else @as(u32, 0xFFFFFFFF) << @intCast(32 - nbits);
            const network_start = ip & mask;
            const broadcast = network_start | ~mask;

            // Prefix must start exactly at ip and not go past end
            if (network_start == ip and broadcast <= end) {
                break;
            }
            nbits += 1;
        }

        // Create network with this prefix
        var net: IPv4Network = undefined;
        net.network_address = IPv4Address.fromInt(ip);
        net.prefixlen = nbits;

        try networks.append(allocator, net);

        // Move to next address after this network
        const mask = if (nbits == 0) 0 else @as(u32, 0xFFFFFFFF) << @intCast(32 - nbits);
        const broadcast = ip | ~mask;
        if (broadcast == 0xFFFFFFFF) break; // Avoid overflow
        ip = broadcast + 1;
    }

    return networks.toOwnedSlice(allocator);
}

//! CPython source: Lib/ipaddress.py
//!
//! Provides classes for working with IP addresses and networks.
//!
//! Mirrors: CPython Lib/ipaddress.py

const std = @import("std");

// Re-export all public types and functions
pub const errors = @import("ipaddress/errors.zig");
pub const constants = @import("ipaddress/constants.zig");
pub const ipv4 = @import("ipaddress/ipv4.zig");
pub const ipv6 = @import("ipaddress/ipv6.zig");
pub const utils = @import("ipaddress/utils.zig");

// Re-export commonly used types and constants
pub const AddressValueError = errors.AddressValueError;
pub const IPV4 = constants.IPV4;
pub const IPV6 = constants.IPV6;

// Re-export IPv4 types
pub const IPv4Address = ipv4.IPv4Address;
pub const IPv4Network = ipv4.IPv4Network;
pub const IPv4Interface = ipv4.IPv4Interface;

// Re-export IPv6 types
pub const IPv6Address = ipv6.IPv6Address;
pub const IPv6Network = ipv6.IPv6Network;
pub const IPv6Interface = ipv6.IPv6Interface;

// Re-export utility functions
pub const ip_address = utils.ip_address;
pub const ip_network = utils.ip_network;
pub const ip_interface = utils.ip_interface;
pub const collapse_addresses = utils.collapse_addresses;
pub const summarize_address_range = utils.summarize_address_range;

// ============================================================================
// Tests
// ============================================================================

test "IPv4Address init" {
    const addr = try IPv4Address.init("192.168.1.1");
    try std.testing.expectEqual(@as(u32, 0xC0A80101), addr._packed);
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
    try std.testing.expectEqual(@as(u32, 0xC0A80100), net.network_address._packed);
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
    try std.testing.expectEqual(@as(u32, 0xC0A80164), iface.address._packed);
    try std.testing.expectEqual(@as(u8, 24), iface.network.prefixlen);
}

test "IPv6Address init simple" {
    const addr = try IPv6Address.init("::1");
    try std.testing.expectEqual(@as(u128, 1), addr._packed);
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

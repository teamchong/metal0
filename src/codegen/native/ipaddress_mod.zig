/// Python ipaddress module - IPv4/IPv6 manipulation library
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ip_address", h.wrap("blk: { const addr = ", "; break :blk .{ .address = addr, .version = @as(i32, 4) }; }", ".{ .address = \"0.0.0.0\", .version = @as(i32, 4) }") },
    .{ "ip_network", h.wrap("blk: { const addr = ", "; break :blk .{ .network_address = addr, .prefixlen = @as(i32, 24), .version = @as(i32, 4) }; }", ".{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0), .version = @as(i32, 4) }") },
    .{ "ip_interface", h.wrap("blk: { const addr = ", "; break :blk .{ .ip = .{ .address = addr }, .network = .{ .network_address = addr, .prefixlen = @as(i32, 24) } }; }", ".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }") },
    .{ "IPv4Address", h.wrap("blk: { const addr = ", "; break :blk .{ .address = addr, .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }; }", ".{ .address = \"0.0.0.0\", .version = @as(i32, 4), .max_prefixlen = @as(i32, 32), .packed = &[_]u8{0, 0, 0, 0} }") },
    .{ "IPv4Network", h.c(".{ .network_address = \"0.0.0.0\", .broadcast_address = \"0.0.0.0\", .netmask = \"0.0.0.0\", .hostmask = \"255.255.255.255\", .prefixlen = @as(i32, 0), .num_addresses = @as(i64, 1), .version = @as(i32, 4) }") },
    .{ "IPv4Interface", h.c(".{ .ip = .{ .address = \"0.0.0.0\" }, .network = .{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) } }") },
    .{ "IPv6Address", h.wrap("blk: { const addr = ", "; break :blk .{ .address = addr, .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }; }", ".{ .address = \"::\", .version = @as(i32, 6), .max_prefixlen = @as(i32, 128), .packed = &[_]u8{0} ** 16 }") },
    .{ "IPv6Network", h.c(".{ .network_address = \"::\", .broadcast_address = \"::\", .netmask = \"::\", .hostmask = \"::\", .prefixlen = @as(i32, 0), .num_addresses = @as(i128, 1), .version = @as(i32, 6) }") },
    .{ "IPv6Interface", h.c(".{ .ip = .{ .address = \"::\" }, .network = .{ .network_address = \"::\", .prefixlen = @as(i32, 0) } }") },
    .{ "v4_int_to_packed", h.c("&[_]u8{0, 0, 0, 0}") }, .{ "v6_int_to_packed", h.c("&[_]u8{0} ** 16") },
    .{ "summarize_address_range", h.c("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}") },
    .{ "collapse_addresses", h.c("&[_]@TypeOf(.{ .network_address = \"0.0.0.0\", .prefixlen = @as(i32, 0) }){}") },
    .{ "get_mixed_type_key", h.c(".{ @as(i32, 4), @as(?*anyopaque, null) }") },
    .{ "AddressValueError", h.err("AddressValueError") }, .{ "NetmaskValueError", h.err("NetmaskValueError") },
});

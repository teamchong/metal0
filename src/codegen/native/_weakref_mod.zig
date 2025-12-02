/// Python _weakref module - Weak reference support (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ref", h.wrap("blk: { const obj = ", "; break :blk .{ .ptr = @intFromPtr(&obj) }; }", ".{ .ptr = 0 }") },
    .{ "proxy", h.pass("null") }, .{ "getweakrefcount", h.I64(0) },
    .{ "getweakrefs", h.c("&[_]@TypeOf(.{}){}") }, .{ "CallableProxyType", h.c("@TypeOf(.{})") },
    .{ "ProxyType", h.c("@TypeOf(.{})") }, .{ "ReferenceType", h.c("@TypeOf(.{})") },
});

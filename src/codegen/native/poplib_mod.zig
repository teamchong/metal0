/// Python poplib module - POP3 protocol client
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "POP3", h.c(".{ .host = \"\", .port = @as(i32, 110), .timeout = @as(f64, -1.0) }") },
    .{ "POP3_SSL", h.c(".{ .host = \"\", .port = @as(i32, 995), .timeout = @as(f64, -1.0) }") },
    .{ "POP3_PORT", h.I32(110) }, .{ "POP3_SSL_PORT", h.I32(995) },
    .{ "error_proto", h.err("POP3ProtoError") },
});

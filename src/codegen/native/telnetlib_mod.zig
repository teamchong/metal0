/// Python telnetlib module - Telnet client class
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Telnet", h.c(".{ .host = @as(?[]const u8, null), .port = @as(i32, 23), .timeout = @as(f64, -1.0), .sock = @as(?*anyopaque, null) }") },
    .{ "TELNET_PORT", h.I32(23) },
    .{ "THEOPT", h.U8(0) }, .{ "ECHO", h.U8(1) }, .{ "SGA", h.U8(3) }, .{ "TTYPE", h.U8(24) },
    .{ "NAWS", h.U8(31) }, .{ "LINEMODE", h.U8(34) }, .{ "XDISPLOC", h.U8(35) },
    .{ "AUTHENTICATION", h.U8(37) }, .{ "ENCRYPT", h.U8(38) }, .{ "NEW_ENVIRON", h.U8(39) },
    .{ "SE", h.U8(240) }, .{ "NOP", h.U8(241) }, .{ "DM", h.U8(242) }, .{ "BRK", h.U8(243) },
    .{ "IP", h.U8(244) }, .{ "AO", h.U8(245) }, .{ "AYT", h.U8(246) }, .{ "EC", h.U8(247) },
    .{ "EL", h.U8(248) }, .{ "GA", h.U8(249) }, .{ "SB", h.U8(250) }, .{ "WILL", h.U8(251) },
    .{ "WONT", h.U8(252) }, .{ "DO", h.U8(253) }, .{ "DONT", h.U8(254) }, .{ "IAC", h.U8(255) },
});

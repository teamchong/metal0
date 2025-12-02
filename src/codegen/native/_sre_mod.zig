/// Python _sre module - Internal SRE support (C accelerator for regex)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", h.wrap("blk: { const pat = ", "; _ = pat; break :blk .{ .pattern = pat, .flags = 0, .groups = 0 }; }", ".{ .pattern = \"\", .flags = 0, .groups = 0 }") },
    .{ "c_o_d_e_s_i_z_e", h.I32(4) }, .{ "m_a_g_i_c", h.I32(20171005) },
    .{ "getlower", h.pass("@as(i32, 0)") }, .{ "getcodesize", h.I32(4) },
    .{ "match", h.c("null") }, .{ "fullmatch", h.c("null") }, .{ "search", h.c("null") },
    .{ "findall", h.c("&[_][]const u8{}") }, .{ "finditer", h.c("&[_]@TypeOf(null){}") },
    .{ "sub", h.passN(1, "\"\"") }, .{ "subn", h.wrapN(1, ".{ ", ", @as(i64, 0) }", ".{ \"\", @as(i64, 0) }") },
    .{ "split", h.c("&[_][]const u8{}") },
    .{ "group", h.c("\"\"") }, .{ "groups", h.c(".{}") }, .{ "groupdict", h.c(".{}") },
    .{ "start", h.I64(0) }, .{ "end", h.I64(0) }, .{ "span", h.c(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "expand", h.c("\"\"") },
});

/// Python _markupbase module - Internal markup base support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parser_base", h.c(".{ .lasttag = \"\", .interesting = null }") }, .{ "reset", h.c("{}") },
    .{ "getpos", h.c(".{ @as(i64, 1), @as(i64, 0) }") }, .{ "updatepos", h.c("@as(i64, 0)") }, .{ "error", h.err("ParserError") },
});

/// Python nis module - NIS (Yellow Pages) interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "match", h.c("\"\"") }, .{ "cat", h.c(".{}") },
    .{ "maps", h.c("&[_][]const u8{}") }, .{ "get_default_domain", h.c("\"\"") },
    .{ "error", h.err("NisError") },
});

/// Python _dbm module - Internal dbm support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.c(".{}") }, .{ "error", h.err("DbmError") }, .{ "close", h.c("{}") },
    .{ "keys", h.c("&[_][]const u8{}") }, .{ "get", h.c("null") }, .{ "setdefault", h.c("\"\"") },
});

/// Python _gdbm module - GNU DBM database
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.c(".{}") }, .{ "close", h.c("{}") }, .{ "keys", h.c("&[_][]const u8{}") },
    .{ "firstkey", h.c("null") }, .{ "nextkey", h.c("null") }, .{ "reorganize", h.c("{}") }, .{ "sync", h.c("{}") }, .{ "error", h.err("GdbmError") },
});

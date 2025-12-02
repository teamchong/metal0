/// Python plistlib module - Apple plist file handling
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "load", h.c(".{}") }, .{ "loads", h.c(".{}") }, .{ "dump", h.c("{}") }, .{ "dumps", h.c("\"\"") },
    .{ "UID", h.wrap("blk: { const data = ", "; break :blk .{ .data = data }; }", ".{ .data = @as(i64, 0) }") },
    .{ "FMT_XML", h.I32(1) }, .{ "FMT_BINARY", h.I32(2) },
    .{ "Dict", h.c(".{}") }, .{ "Data", h.pass("\"\"") }, .{ "InvalidFileException", h.err("InvalidFileException") },
    .{ "readPlist", h.c(".{}") }, .{ "writePlist", h.c("{}") }, .{ "readPlistFromBytes", h.c(".{}") }, .{ "writePlistToBytes", h.c("\"\"") },
});

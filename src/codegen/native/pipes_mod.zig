/// Python pipes module - Interface to shell pipelines (deprecated in 3.11)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Template", h.c(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "reset", h.c("{}") },
    .{ "clone", h.c(".{ .steps = &[_][]const u8{}, .debugging = false }") }, .{ "debug", h.c("{}") },
    .{ "append", h.c("{}") }, .{ "prepend", h.c("{}") }, .{ "open", h.c("null") }, .{ "copy", h.c("{}") },
    .{ "FILEIN_FILEOUT", h.c("\"ff\"") }, .{ "STDIN_FILEOUT", h.c("\"-f\"") },
    .{ "FILEIN_STDOUT", h.c("\"f-\"") }, .{ "STDIN_STDOUT", h.c("\"--\"") },
    .{ "quote", h.wrap("blk: { const s = ", "; _ = s; break :blk \"''\"; }", "\"''\"") },
});

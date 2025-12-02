/// Python _compression module - Internal compression support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "DecompressReader", h.c(".{ .fp = null, .decomp = null, .eof = false, .pos = 0, .size = -1 }") }, .{ "BaseStream", h.c(".{}") },
    .{ "readable", h.c("true") }, .{ "writable", h.c("false") }, .{ "seekable", h.c("true") },
    .{ "read", h.c("\"\"") }, .{ "read1", h.c("\"\"") }, .{ "readline", h.c("\"\"") },
    .{ "readlines", h.c("&[_][]const u8{}") }, .{ "readinto", h.c("@as(usize, 0)") },
    .{ "seek", h.I64(0) }, .{ "tell", h.I64(0) }, .{ "close", h.c("{}") },
});

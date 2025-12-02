/// Python shlex module - Simple lexical analysis (shell tokenizer)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "split", h.c("&[_][]const u8{}") }, .{ "join", h.c("\"\"") },
    .{ "shlex", h.c(".{ .instream = @as(?*anyopaque, null), .infile = \"\", .posix = true, .eof = \"\", .commenters = \"#\", .wordchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .whitespace = \" \\t\\r\\n\", .whitespace_split = false, .quotes = \"'\\\"\" }") },
    .{ "quote", h.wrap("blk: { const s = ", "; break :blk s; }", "\"''\"") },
});

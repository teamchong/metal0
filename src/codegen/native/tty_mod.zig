/// Python tty module - Terminal control functions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "setraw", h.c("{}") },
    .{ "setcbreak", h.c("{}") },
    .{ "isatty", h.wrap("std.posix.isatty(@intCast(", "))", "false") },
});

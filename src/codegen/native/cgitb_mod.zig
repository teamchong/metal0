/// Python cgitb module - Traceback manager for CGI scripts (deprecated 3.11)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "enable", h.c("{}") }, .{ "handler", h.c("{}") }, .{ "text", h.c("\"\"") },
    .{ "html", h.c("\"<html></html>\"") }, .{ "reset", h.c("{}") },
    .{ "Hook", h.c(".{ .display = 1, .logdir = null, .context = 5, .file = null, .format = \"html\" }") },
});

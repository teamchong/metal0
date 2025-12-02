/// Python cmd module - Command-line interpreter framework
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Cmd", h.c(".{ .prompt = \"(Cmd) \", .intro = null, .identchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .ruler = \"=\", .lastcmd = \"\", .cmdqueue = &[_][]const u8{}, .completekey = \"tab\", .use_rawinput = true }") },
});

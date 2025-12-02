/// Python rlcompleter module - Readline completion support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Completer", h.c(".{ .namespace = .{}, .use_main_ns = @as(i32, 0) }") },
});

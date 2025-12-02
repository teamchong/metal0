/// Python antigravity module - Easter egg (opens xkcd comic)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "init", h.c("{}") },
    .{ "geohash", h.F64(0.0) },
});

/// Python profile/cProfile module - Performance profiling
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Profile", h.c(".{ .stats = @as(?*anyopaque, null) }") },
    .{ "run", h.c("{}") }, .{ "runctx", h.c("{}") },
});

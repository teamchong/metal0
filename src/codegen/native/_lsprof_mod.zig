/// Python _lsprof module - Internal profiler support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "profiler", h.c(".{ .timer = null, .timeunit = 0.0, .subcalls = true, .builtins = true }") }, .{ "enable", h.c("{}") }, .{ "disable", h.c("{}") }, .{ "clear", h.c("{}") },
    .{ "getstats", h.c("&[_]@TypeOf(.{}){}") }, .{ "profiler_entry", h.c(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0, .calls = null }") },
    .{ "profiler_subentry", h.c(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0 }") },
});

/// Python timeit module - Measure execution time
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "timeit", h.F64(0.0) },
    .{ "repeat", h.c("&[_]f64{}") },
    .{ "default_timer", h.c("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0") },
    .{ "Timer", h.c(".{ .stmt = \"pass\", .setup = \"pass\", .timer = @as(?*const fn () f64, null), .globals = @as(?*anyopaque, null) }") },
});

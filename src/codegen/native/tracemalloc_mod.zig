/// Python tracemalloc module - Trace memory allocations
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start", h.c("{}") }, .{ "stop", h.c("{}") }, .{ "is_tracing", h.c("false") }, .{ "clear_traces", h.c("{}") },
    .{ "get_object_traceback", h.c("null") }, .{ "get_traceback_limit", h.I32(1) },
    .{ "get_traced_memory", h.c(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "reset_peak", h.c("{}") }, .{ "get_tracemalloc_memory", h.I64(0) },
    .{ "take_snapshot", h.c(".{ .traces = &[_]@TypeOf(.{}){} }") }, .{ "Snapshot", h.c(".{ .traces = &[_]@TypeOf(.{}){} }") },
    .{ "Statistic", h.c(".{ .traceback = null, .size = 0, .count = 0 }") },
    .{ "StatisticDiff", h.c(".{ .traceback = null, .size = 0, .size_diff = 0, .count = 0, .count_diff = 0 }") },
    .{ "Trace", h.c(".{ .traceback = null, .size = 0 }") },
    .{ "Traceback", h.c(".{ .frames = &[_]@TypeOf(.{}){} }") },
    .{ "Frame", h.c(".{ .filename = \"\", .lineno = 0 }") },
    .{ "Filter", h.c(".{ .inclusive = true, .filename_pattern = \"*\", .lineno = null, .all_frames = false, .domain = null }") },
    .{ "DomainFilter", h.c(".{ .inclusive = true, .domain = 0 }") },
});

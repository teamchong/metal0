/// Python _tracemalloc module - Internal tracemalloc support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start", h.c("{}") }, .{ "stop", h.c("{}") }, .{ "is_tracing", h.c("false") }, .{ "clear_traces", h.c("{}") },
    .{ "get_traceback_limit", h.I32(1) }, .{ "get_traced_memory", h.c(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "reset_peak", h.c("{}") },
    .{ "get_tracemalloc_memory", h.I64(0) }, .{ "get_object_traceback", h.c("null") }, .{ "get_traces", h.c("&[_]@TypeOf(.{}){}") },
    .{ "get_object_traceback_internal", h.c("null") },
});

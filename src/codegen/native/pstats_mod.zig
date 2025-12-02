/// Python pstats module - Statistics object for the profiler
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Stats", h.c(".{ .stats = .{}, .total_calls = 0, .prim_calls = 0, .total_tt = 0.0, .stream = null }") },
    .{ "SortKey", h.c(".{ .CALLS = 0, .CUMULATIVE = 1, .FILENAME = 2, .LINE = 3, .NAME = 4, .NFL = 5, .PCALLS = 6, .STDNAME = 7, .TIME = 8 }") },
    .{ "strip_dirs", h.c(".{}") }, .{ "add", h.c(".{}") },
    .{ "dump_stats", h.c("{}") }, .{ "sort_stats", h.c(".{}") }, .{ "reverse_order", h.c(".{}") },
    .{ "print_stats", h.c(".{}") }, .{ "print_callers", h.c(".{}") }, .{ "print_callees", h.c(".{}") },
    .{ "get_stats_profile", h.c(".{ .total_tt = 0.0, .func_profiles = .{} }") },
    .{ "FunctionProfile", h.c(".{ .ncalls = 0, .tottime = 0.0, .percall_tottime = 0.0, .cumtime = 0.0, .percall_cumtime = 0.0, .file_name = \"\", .line_number = 0 }") },
    .{ "StatsProfile", h.c(".{ .total_tt = 0.0, .func_profiles = .{} }") },
});

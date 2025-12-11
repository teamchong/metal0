//! Printing functionality for profile statistics
//!
//! Provides methods for displaying profiling data in various formats:
//! - printStats: Print function statistics table
//! - printCallers: Print caller information
//! - printCallees: Print callee information

const std = @import("std");
const types = @import("types.zig");
const sorting = @import("sorting.zig");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Print Statistics
// ============================================================================

/// Print statistics to a writer
pub fn printStats(
    allocator: std.mem.Allocator,
    stream: std.fs.File,
    stats: hashmap_helper.StringHashMap(types.FuncStat),
    sort_keys: []const types.SortKey,
    total_calls: usize,
    primitive_calls: usize,
    total_time: f64,
    restrictions: ?[]const []const u8,
) !void {
    const writer = stream.writer();

    // Header
    try writer.print("         {d} function calls", .{total_calls});
    if (primitive_calls != total_calls) {
        try writer.print(" ({d} primitive calls)", .{primitive_calls});
    }
    try writer.print(" in {d:.3} seconds\n\n", .{total_time});

    // Column headers
    try writer.writeAll("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)\n");

    // Get sorted stats
    var entries = std.ArrayList(sorting.Entry).init(allocator);
    defer entries.deinit();

    var it = stats.iterator();
    while (it.next()) |entry| {
        try entries.append(.{
            .key = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        });
    }

    // Sort by current sort keys
    const sort_ctx = sorting.SortContext{ .keys = sort_keys };
    std.mem.sort(sorting.Entry, entries.items, sort_ctx, sorting.SortContext.lessThan);

    // Apply restrictions
    var count: usize = 0;
    for (entries.items) |entry| {
        if (restrictions) |r| {
            var matches = false;
            for (r) |pattern| {
                if (std.mem.indexOf(u8, entry.key, pattern) != null) {
                    matches = true;
                    break;
                }
            }
            if (!matches) continue;
        }

        const stat = entry.value;
        const percall_tot = if (stat.primitive_calls > 0)
            stat.total_time / @as(f64, @floatFromInt(stat.primitive_calls))
        else
            0;
        const percall_cum = if (stat.primitive_calls > 0)
            stat.cumulative_time / @as(f64, @floatFromInt(stat.primitive_calls))
        else
            0;

        if (stat.total_calls == stat.primitive_calls) {
            try writer.print("{d:9}", .{stat.total_calls});
        } else {
            try writer.print("{d}/{d}", .{ stat.total_calls, stat.primitive_calls });
        }

        try writer.print("  {d:7.3}  {d:7.3}  {d:7.3}  {d:7.3}  {s}\n", .{
            stat.total_time,
            percall_tot,
            stat.cumulative_time,
            percall_cum,
            entry.key,
        });

        count += 1;
    }

    try writer.print("\n{d} entries printed\n", .{count});
}

// ============================================================================
// Print Callers
// ============================================================================

/// Print callers of functions
pub fn printCallers(
    allocator: std.mem.Allocator,
    stream: std.fs.File,
    stats: hashmap_helper.StringHashMap(types.FuncStat),
    restrictions: ?[]const []const u8,
) !void {
    const writer = stream.writer();
    try writer.writeAll("   Ordered by: standard name\n\n");
    try writer.writeAll("Function                          was called by...\n");
    try writer.writeAll("                                      ncalls  tottime  cumtime\n");

    var it = stats.iterator();
    while (it.next()) |entry| {
        if (restrictions) |r| {
            var matches = false;
            for (r) |pattern| {
                if (std.mem.indexOf(u8, entry.key_ptr.*, pattern) != null) {
                    matches = true;
                    break;
                }
            }
            if (!matches) continue;
        }

        try writer.print("{s}\n", .{entry.key_ptr.*});

        var callers_it = entry.value_ptr.callers.iterator();
        while (callers_it.next()) |caller_entry| {
            const caller_id = caller_entry.key_ptr.*;
            const caller_info = caller_entry.value_ptr.*;

            const caller_str = try caller_id.format(allocator);
            defer allocator.free(caller_str);

            try writer.print("    {s}  {d}  {d:.3}  {d:.3}\n", .{
                caller_str,
                caller_info.calls,
                caller_info.total_time,
                caller_info.cumulative_time,
            });
        }
    }
}

// ============================================================================
// Print Callees
// ============================================================================

/// Print what functions call (callee statistics)
pub fn printCallees(
    stream: std.fs.File,
    stats: hashmap_helper.StringHashMap(types.FuncStat),
    restrictions: ?[]const []const u8,
) !void {
    const writer = stream.writer();
    try writer.writeAll("   Ordered by: standard name\n\n");
    try writer.writeAll("Function                          called...\n");
    try writer.writeAll("                                      ncalls  tottime  cumtime\n");

    _ = restrictions;

    // Iterate through all functions and print their callee info
    var it = stats.iterator();
    while (it.next()) |entry| {
        const stat = entry.value_ptr.*;
        try writer.print("{s}\n", .{entry.key_ptr.*});

        // Print callers (which represents who called this function)
        // In pstats, we need to reverse this to show callees
        var caller_it = stat.callers.iterator();
        while (caller_it.next()) |caller_entry| {
            const caller_id = caller_entry.key_ptr.*;
            const info = caller_entry.value_ptr.*;
            try writer.print("    <- {s}:{d}({s})  {d}  {d:.6}  {d:.6}\n", .{
                caller_id.filename,
                caller_id.lineno,
                caller_id.name,
                info.calls,
                info.total_time,
                info.cumulative_time,
            });
        }
    }
}

//! I/O operations for profile statistics
//!
//! Provides functions for loading and saving profiling data:
//! - loadFromFile: Load profile data from disk
//! - dumpStats: Save statistics to a file

const std = @import("std");
const types = @import("types.zig");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Load Operations
// ============================================================================

/// Load profile data from file
pub fn loadFromFile(allocator: std.mem.Allocator, filename: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    // Read marshaled data
    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    return content;
}

/// Load marshaled profile data
pub fn loadMarshaledData(data: []const u8) !void {
    // Simplified marshal format parsing
    // Real implementation would parse Python marshal format
    _ = data;
}

// ============================================================================
// Save Operations
// ============================================================================

/// Dump statistics to file
pub fn dumpStats(
    stats: hashmap_helper.StringHashMap(types.FuncStat),
    filename: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    // Write header
    try file.writeAll("# pstats dump\n");

    // Write stats
    var it = stats.iterator();
    while (it.next()) |entry| {
        const stat = entry.value_ptr.*;
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s},{d},{d},{d:.6},{d:.6}\n", .{
            entry.key_ptr.*,
            stat.primitive_calls,
            stat.total_calls,
            stat.total_time,
            stat.cumulative_time,
        }) catch continue;
        try file.writeAll(line);
    }
}

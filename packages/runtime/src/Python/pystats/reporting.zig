/// Statistics reporting functions
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;
const global = @import("global.zig");

/// Summary of statistics
pub const StatsSummary = struct {
    total_opcodes: u64,
    total_allocs: u64,
    total_calls: u64,
    peak_memory: u64,
    gc_collections: u64,
    gc_time_ms: u64,
};

/// Get summary of current statistics
pub fn getSummary() StatsSummary {
    const stats = global.getStats();

    var total_opcodes: u64 = 0;
    for (stats.opcode_stats) |s| {
        total_opcodes += s.getCount();
    }

    var gc_collections: u64 = 0;
    for (stats.gc_stats.collections) |c| {
        gc_collections += c.load(.monotonic);
    }

    return .{
        .total_opcodes = total_opcodes,
        .total_allocs = stats.alloc_stats.getAllocCount(),
        .total_calls = stats.call_stats.total_calls.load(.monotonic),
        .peak_memory = stats.alloc_stats.getPeakBytes(),
        .gc_collections = gc_collections,
        .gc_time_ms = stats.gc_stats.total_time_ns.load(.monotonic) / 1_000_000,
    };
}

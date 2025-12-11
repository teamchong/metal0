/// Tests for pystats module
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const OpcodeStats = @import("opcode_stats.zig").OpcodeStats;
const AllocStats = @import("alloc_stats.zig").AllocStats;
const CallStats = @import("call_stats.zig").CallStats;
const CallType = @import("call_stats.zig").CallType;
const SpecializationStats = @import("spec_stats.zig").SpecializationStats;
const GCStats = @import("gc_stats.zig").GCStats;

test "opcode stats" {
    var stats = OpcodeStats.init();

    stats.record(100);
    try std.testing.expectEqual(@as(u64, 1), stats.getCount());
    try std.testing.expectEqual(@as(u64, 100), stats.getCycles());

    stats.record(50);
    try std.testing.expectEqual(@as(u64, 2), stats.getCount());
    try std.testing.expectEqual(@as(u64, 150), stats.getCycles());
}

test "alloc stats" {
    var stats = AllocStats{};

    stats.recordAlloc(100);
    try std.testing.expectEqual(@as(u64, 1), stats.getAllocCount());
    try std.testing.expectEqual(@as(i64, 100), stats.getCurrentBytes());

    stats.recordAlloc(200);
    try std.testing.expectEqual(@as(i64, 300), stats.getCurrentBytes());
    try std.testing.expectEqual(@as(u64, 300), stats.getPeakBytes());

    stats.recordFree(100);
    try std.testing.expectEqual(@as(u64, 1), stats.getFreeCount());
    try std.testing.expectEqual(@as(i64, 200), stats.getCurrentBytes());
    try std.testing.expectEqual(@as(u64, 300), stats.getPeakBytes()); // Peak unchanged
}

test "call stats" {
    var stats = CallStats.init();

    stats.recordCall(.python, 1);
    stats.recordCall(.c, 2);
    stats.recordCall(.builtin, 3);

    try std.testing.expectEqual(@as(u64, 3), stats.total_calls.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.python_calls.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.c_calls.load(.monotonic));
    try std.testing.expectEqual(@as(u32, 3), stats.max_depth.load(.monotonic));
}

test "specialization stats" {
    var stats = SpecializationStats{};

    stats.recordHit();
    stats.recordHit();
    stats.recordMiss();

    try std.testing.expectEqual(@as(u64, 2), stats.hits.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), stats.misses.load(.monotonic));

    const rate = stats.hitRate();
    try std.testing.expect(rate > 0.65 and rate < 0.68);
}

test "gc stats" {
    var stats = GCStats.init();

    stats.recordCollection(0, 100, 5, 1_000_000);
    stats.recordCollection(1, 50, 2, 2_000_000);

    try std.testing.expectEqual(@as(u64, 1), stats.collections[0].load(.monotonic));
    try std.testing.expectEqual(@as(u64, 100), stats.collected[0].load(.monotonic));
    try std.testing.expectEqual(@as(u64, 3_000_000), stats.total_time_ns.load(.monotonic));
}

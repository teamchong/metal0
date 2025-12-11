/// Type specialization statistics
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;

/// Statistics for type specialization
pub const SpecializationStats = struct {
    /// Hits (specialized code executed)
    hits: Atomic(u64) = Atomic(u64).init(0),
    /// Misses (generic code executed)
    misses: Atomic(u64) = Atomic(u64).init(0),
    /// Deferred (waiting to specialize)
    deferred: Atomic(u64) = Atomic(u64).init(0),
    /// Deoptimized (reverted to generic)
    deopt: Atomic(u64) = Atomic(u64).init(0),

    const Self = @This();

    pub fn recordHit(self: *Self) void {
        _ = self.hits.fetchAdd(1, .monotonic);
    }

    pub fn recordMiss(self: *Self) void {
        _ = self.misses.fetchAdd(1, .monotonic);
    }

    pub fn recordDefer(self: *Self) void {
        _ = self.deferred.fetchAdd(1, .monotonic);
    }

    pub fn recordDeopt(self: *Self) void {
        _ = self.deopt.fetchAdd(1, .monotonic);
    }

    pub fn hitRate(self: *const Self) f64 {
        const h = self.hits.load(.monotonic);
        const m = self.misses.load(.monotonic);
        const total = h + m;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(h)) / @as(f64, @floatFromInt(total));
    }
};

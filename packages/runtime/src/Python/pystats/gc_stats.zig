/// Garbage collection statistics
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;

/// Statistics for garbage collection
pub const GCStats = struct {
    /// Number of collections per generation
    collections: [3]Atomic(u64) = undefined,
    /// Objects collected per generation
    collected: [3]Atomic(u64) = undefined,
    /// Uncollectable objects per generation
    uncollectable: [3]Atomic(u64) = undefined,
    /// Total GC time in nanoseconds
    total_time_ns: Atomic(u64) = Atomic(u64).init(0),

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.collections) |*c| {
            c.* = Atomic(u64).init(0);
        }
        for (&self.collected) |*c| {
            c.* = Atomic(u64).init(0);
        }
        for (&self.uncollectable) |*c| {
            c.* = Atomic(u64).init(0);
        }
        return self;
    }

    pub fn recordCollection(self: *Self, generation: u8, collected_count: u64, uncollectable_count: u64, time_ns: u64) void {
        if (generation < 3) {
            _ = self.collections[generation].fetchAdd(1, .monotonic);
            _ = self.collected[generation].fetchAdd(collected_count, .monotonic);
            _ = self.uncollectable[generation].fetchAdd(uncollectable_count, .monotonic);
        }
        _ = self.total_time_ns.fetchAdd(time_ns, .monotonic);
    }
};

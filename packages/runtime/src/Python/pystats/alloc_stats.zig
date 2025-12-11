/// Memory allocation statistics
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;

/// Statistics for memory allocations
pub const AllocStats = struct {
    /// Number of allocations
    alloc_count: Atomic(u64) = Atomic(u64).init(0),
    /// Number of frees
    free_count: Atomic(u64) = Atomic(u64).init(0),
    /// Current allocated bytes
    current_bytes: Atomic(i64) = Atomic(i64).init(0),
    /// Peak allocated bytes
    peak_bytes: Atomic(u64) = Atomic(u64).init(0),
    /// Total bytes ever allocated
    total_bytes: Atomic(u64) = Atomic(u64).init(0),

    const Self = @This();

    pub fn recordAlloc(self: *Self, size: usize) void {
        _ = self.alloc_count.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(size, .monotonic);

        const current = self.current_bytes.fetchAdd(@intCast(size), .monotonic) + @as(i64, @intCast(size));
        if (current > 0) {
            // Update peak if necessary
            const current_u: u64 = @intCast(current);
            var peak = self.peak_bytes.load(.monotonic);
            while (current_u > peak) {
                const result = self.peak_bytes.cmpxchgWeak(peak, current_u, .monotonic, .monotonic);
                if (result) |new_peak| {
                    peak = new_peak;
                } else {
                    break;
                }
            }
        }
    }

    pub fn recordFree(self: *Self, size: usize) void {
        _ = self.free_count.fetchAdd(1, .monotonic);
        _ = self.current_bytes.fetchSub(@intCast(size), .monotonic);
    }

    pub fn getAllocCount(self: *const Self) u64 {
        return self.alloc_count.load(.monotonic);
    }

    pub fn getFreeCount(self: *const Self) u64 {
        return self.free_count.load(.monotonic);
    }

    pub fn getCurrentBytes(self: *const Self) i64 {
        return self.current_bytes.load(.monotonic);
    }

    pub fn getPeakBytes(self: *const Self) u64 {
        return self.peak_bytes.load(.monotonic);
    }
};

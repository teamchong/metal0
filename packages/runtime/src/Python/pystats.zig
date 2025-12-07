/// pystats - Python Statistics
/// Mirrors cpython/Python/pystats.c
///
/// This module provides runtime statistics collection:
/// - Opcode execution counts
/// - Object allocation statistics
/// - Call statistics
/// - Type specialization stats
/// - GC statistics

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of opcodes to track
pub const MAX_OPCODES: usize = 256;

/// Maximum call depth for profiling
pub const MAX_CALL_DEPTH: usize = 100;

/// Number of type specialization entries
pub const SPECIALIZATION_ENTRIES: usize = 64;

// ============================================================================
// Opcode Statistics
// ============================================================================

/// Statistics for a single opcode
pub const OpcodeStats = struct {
    /// Execution count
    count: Atomic(u64) = Atomic(u64).init(0),
    /// Total cycles spent
    cycles: Atomic(u64) = Atomic(u64).init(0),
    /// Pair execution (this opcode followed by...)
    pair_counts: [MAX_OPCODES]Atomic(u64) = undefined,

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.pair_counts) |*p| {
            p.* = Atomic(u64).init(0);
        }
        return self;
    }

    pub fn record(self: *Self, cycles_spent: u64) void {
        _ = self.count.fetchAdd(1, .monotonic);
        _ = self.cycles.fetchAdd(cycles_spent, .monotonic);
    }

    pub fn recordPair(self: *Self, next_opcode: u8) void {
        _ = self.pair_counts[next_opcode].fetchAdd(1, .monotonic);
    }

    pub fn getCount(self: *const Self) u64 {
        return self.count.load(.monotonic);
    }

    pub fn getCycles(self: *const Self) u64 {
        return self.cycles.load(.monotonic);
    }
};

// ============================================================================
// Allocation Statistics
// ============================================================================

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

// ============================================================================
// Call Statistics
// ============================================================================

/// Statistics for function calls
pub const CallStats = struct {
    /// Total calls
    total_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Calls to Python functions
    python_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Calls to C functions
    c_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Method calls
    method_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Builtin calls
    builtin_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Generator/coroutine calls
    generator_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Maximum call depth seen
    max_depth: Atomic(u32) = Atomic(u32).init(0),
    /// Call depth histogram
    depth_histogram: [MAX_CALL_DEPTH]Atomic(u64) = undefined,

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.depth_histogram) |*h| {
            h.* = Atomic(u64).init(0);
        }
        return self;
    }

    pub fn recordCall(self: *Self, call_type: CallType, depth: u32) void {
        _ = self.total_calls.fetchAdd(1, .monotonic);

        switch (call_type) {
            .python => _ = self.python_calls.fetchAdd(1, .monotonic),
            .c => _ = self.c_calls.fetchAdd(1, .monotonic),
            .method => _ = self.method_calls.fetchAdd(1, .monotonic),
            .builtin => _ = self.builtin_calls.fetchAdd(1, .monotonic),
            .generator => _ = self.generator_calls.fetchAdd(1, .monotonic),
        }

        // Update max depth
        var max_d = self.max_depth.load(.monotonic);
        while (depth > max_d) {
            const result = self.max_depth.cmpxchgWeak(max_d, depth, .monotonic, .monotonic);
            if (result) |new_max| {
                max_d = new_max;
            } else {
                break;
            }
        }

        // Record in histogram
        if (depth < MAX_CALL_DEPTH) {
            _ = self.depth_histogram[depth].fetchAdd(1, .monotonic);
        }
    }
};

/// Call types
pub const CallType = enum {
    python,
    c,
    method,
    builtin,
    generator,
};

// ============================================================================
// Type Specialization Statistics
// ============================================================================

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

// ============================================================================
// GC Statistics
// ============================================================================

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

// ============================================================================
// Global Statistics
// ============================================================================

/// Global statistics container
pub const PyStats = struct {
    /// Opcode statistics
    opcode_stats: [MAX_OPCODES]OpcodeStats = undefined,
    /// Allocation statistics
    alloc_stats: AllocStats = .{},
    /// Call statistics
    call_stats: CallStats = undefined,
    /// Specialization statistics per opcode
    spec_stats: [MAX_OPCODES]SpecializationStats = undefined,
    /// GC statistics
    gc_stats: GCStats = undefined,
    /// Whether stats collection is enabled
    enabled: bool = false,

    const Self = @This();

    pub fn init() Self {
        var self = Self{
            .call_stats = CallStats.init(),
            .gc_stats = GCStats.init(),
        };
        for (&self.opcode_stats) |*s| {
            s.* = OpcodeStats.init();
        }
        for (&self.spec_stats) |*s| {
            s.* = .{};
        }
        return self;
    }

    /// Enable statistics collection
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable statistics collection
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Reset all statistics
    pub fn reset(self: *Self) void {
        self.* = Self.init();
    }
};

// ============================================================================
// Global State
// ============================================================================

var g_stats: PyStats = PyStats.init();

/// Get global statistics
pub fn getStats() *PyStats {
    return &g_stats;
}

/// Enable statistics collection
pub fn enable() void {
    g_stats.enable();
}

/// Disable statistics collection
pub fn disable() void {
    g_stats.disable();
}

/// Check if statistics are enabled
pub fn isEnabled() bool {
    return g_stats.enabled;
}

/// Reset all statistics
pub fn reset() void {
    g_stats.reset();
}

// ============================================================================
// Convenience Recording Functions
// ============================================================================

/// Record opcode execution
pub fn recordOpcode(opcode: u8, cycles: u64) void {
    if (!g_stats.enabled) return;
    g_stats.opcode_stats[opcode].record(cycles);
}

/// Record opcode pair
pub fn recordOpcodePair(opcode: u8, next_opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.opcode_stats[opcode].recordPair(next_opcode);
}

/// Record allocation
pub fn recordAlloc(size: usize) void {
    if (!g_stats.enabled) return;
    g_stats.alloc_stats.recordAlloc(size);
}

/// Record free
pub fn recordFree(size: usize) void {
    if (!g_stats.enabled) return;
    g_stats.alloc_stats.recordFree(size);
}

/// Record call
pub fn recordCall(call_type: CallType, depth: u32) void {
    if (!g_stats.enabled) return;
    g_stats.call_stats.recordCall(call_type, depth);
}

/// Record specialization hit
pub fn recordSpecHit(opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.spec_stats[opcode].recordHit();
}

/// Record specialization miss
pub fn recordSpecMiss(opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.spec_stats[opcode].recordMiss();
}

/// Record GC collection
pub fn recordGC(generation: u8, collected: u64, uncollectable: u64, time_ns: u64) void {
    if (!g_stats.enabled) return;
    g_stats.gc_stats.recordCollection(generation, collected, uncollectable, time_ns);
}

// ============================================================================
// Reporting
// ============================================================================

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
    var total_opcodes: u64 = 0;
    for (g_stats.opcode_stats) |s| {
        total_opcodes += s.getCount();
    }

    var gc_collections: u64 = 0;
    for (g_stats.gc_stats.collections) |c| {
        gc_collections += c.load(.monotonic);
    }

    return .{
        .total_opcodes = total_opcodes,
        .total_allocs = g_stats.alloc_stats.getAllocCount(),
        .total_calls = g_stats.call_stats.total_calls.load(.monotonic),
        .peak_memory = g_stats.alloc_stats.getPeakBytes(),
        .gc_collections = gc_collections,
        .gc_time_ms = g_stats.gc_stats.total_time_ns.load(.monotonic) / 1_000_000,
    };
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

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

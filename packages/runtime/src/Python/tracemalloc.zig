/// tracemalloc - Memory Allocation Tracing
/// Mirrors cpython/Python/tracemalloc.c
///
/// This module provides memory allocation tracing for debugging:
/// - Track allocations with source file and line number
/// - Statistics by traceback
/// - Memory snapshots for leak detection
/// - Peak memory tracking

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Maximum traceback depth
pub const MAX_TRACEBACK_DEPTH: usize = 25;

/// Maximum number of tracebacks to store
const MAX_TRACEBACKS: usize = 100_000;

/// Number of hash buckets for allocations
const ALLOCATION_BUCKETS: usize = 65521;

// ============================================================================
// Frame Information
// ============================================================================

/// A single frame in a traceback
pub const Frame = struct {
    filename: []const u8,
    lineno: u32,
    name: []const u8,

    pub fn format(self: Frame, writer: anytype) !void {
        try writer.print("  File \"{s}\", line {d}, in {s}\n", .{
            self.filename,
            self.lineno,
            self.name,
        });
    }
};

/// Traceback - sequence of frames
pub const Traceback = struct {
    frames: []Frame,
    hash: u64,
    refcount: u32,

    pub fn format(self: Traceback, writer: anytype) !void {
        for (self.frames) |frame| {
            try frame.format(writer);
        }
    }
};

// ============================================================================
// Traced Allocation
// ============================================================================

/// A single traced allocation
const TracedAllocation = struct {
    ptr: usize,
    size: usize,
    traceback: ?*Traceback,
    next: ?*TracedAllocation,
};

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for a single traceback
pub const TracebackStats = struct {
    traceback: *Traceback,
    count: usize,
    size: usize,
};

/// Overall tracing statistics
pub const TracingStats = struct {
    /// Number of traced allocations
    traced_count: usize = 0,
    /// Total size of traced allocations
    traced_size: usize = 0,
    /// Peak memory usage
    peak_size: usize = 0,
    /// Number of unique tracebacks
    traceback_count: usize = 0,
};

// ============================================================================
// Tracemalloc State
// ============================================================================

/// Global tracemalloc state
pub const TracemallocState = struct {
    /// Whether tracing is enabled
    enabled: Atomic(bool) = Atomic(bool).init(false),
    /// Maximum traceback depth
    traceback_depth: u32 = MAX_TRACEBACK_DEPTH,
    /// Current stats
    stats: TracingStats = .{},
    /// Allocations hash table
    allocations: [ALLOCATION_BUCKETS]?*TracedAllocation = [_]?*TracedAllocation{null} ** ALLOCATION_BUCKETS,
    /// Lock for thread safety
    mutex: std.Thread.Mutex = .{},
    /// Allocator for internal allocations
    allocator: Allocator,
    /// Domain filtering (0 = all)
    domain: u32 = 0,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.clear();
    }

    /// Start tracing
    pub fn start(self: *Self, nframes: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.traceback_depth = @min(nframes, MAX_TRACEBACK_DEPTH);
        self.enabled.store(true, .release);
    }

    /// Stop tracing
    pub fn stop(self: *Self) void {
        self.enabled.store(false, .release);
    }

    /// Check if tracing is enabled
    pub fn isEnabled(self: *const Self) bool {
        return self.enabled.load(.acquire);
    }

    /// Clear all traces
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (&self.allocations) |*bucket| {
            var current = bucket.*;
            while (current) |alloc| {
                const next = alloc.next;
                self.allocator.destroy(alloc);
                current = next;
            }
            bucket.* = null;
        }

        self.stats = .{};
    }

    /// Record an allocation
    pub fn recordAlloc(self: *Self, ptr: usize, size: usize) void {
        if (!self.isEnabled()) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const bucket_idx = ptr % ALLOCATION_BUCKETS;

        const alloc = self.allocator.create(TracedAllocation) catch return;
        alloc.* = .{
            .ptr = ptr,
            .size = size,
            .traceback = null,
            .next = self.allocations[bucket_idx],
        };
        self.allocations[bucket_idx] = alloc;

        self.stats.traced_count += 1;
        self.stats.traced_size += size;
        if (self.stats.traced_size > self.stats.peak_size) {
            self.stats.peak_size = self.stats.traced_size;
        }
    }

    /// Record a free
    pub fn recordFree(self: *Self, ptr: usize) void {
        if (!self.isEnabled()) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const bucket_idx = ptr % ALLOCATION_BUCKETS;

        var prev: ?*TracedAllocation = null;
        var current = self.allocations[bucket_idx];

        while (current) |alloc| {
            if (alloc.ptr == ptr) {
                // Remove from list
                if (prev) |p| {
                    p.next = alloc.next;
                } else {
                    self.allocations[bucket_idx] = alloc.next;
                }

                self.stats.traced_count -= 1;
                self.stats.traced_size -= alloc.size;

                self.allocator.destroy(alloc);
                return;
            }
            prev = alloc;
            current = alloc.next;
        }
    }

    /// Record a realloc
    pub fn recordRealloc(self: *Self, old_ptr: usize, new_ptr: usize, new_size: usize) void {
        self.recordFree(old_ptr);
        self.recordAlloc(new_ptr, new_size);
    }

    /// Get current statistics
    pub fn getStats(self: *const Self) TracingStats {
        return self.stats;
    }

    /// Get traced memory size
    pub fn getTracedSize(self: *const Self) usize {
        return self.stats.traced_size;
    }

    /// Get peak memory size
    pub fn getPeakSize(self: *const Self) usize {
        return self.stats.peak_size;
    }

    /// Reset peak memory
    pub fn resetPeak(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.stats.peak_size = self.stats.traced_size;
    }

    /// Get allocation by pointer
    pub fn getAllocation(self: *const Self, ptr: usize) ?*const TracedAllocation {
        const bucket_idx = ptr % ALLOCATION_BUCKETS;
        var current = self.allocations[bucket_idx];

        while (current) |alloc| {
            if (alloc.ptr == ptr) {
                return alloc;
            }
            current = alloc.next;
        }

        return null;
    }
};

// ============================================================================
// Global Instance
// ============================================================================

var global_state: ?TracemallocState = null;

/// Get or create global state
pub fn getState() *TracemallocState {
    if (global_state == null) {
        global_state = TracemallocState.init(allocator_helper.fast_allocator);
    }
    return &global_state.?;
}

// ============================================================================
// Public API
// ============================================================================

/// Start tracing with given depth
pub fn start(nframes: u32) void {
    getState().start(nframes);
}

/// Stop tracing
pub fn stop() void {
    getState().stop();
}

/// Check if tracing is enabled
pub fn isEnabled() bool {
    return getState().isEnabled();
}

/// Clear all traces
pub fn clear() void {
    getState().clear();
}

/// Get current traced memory
pub fn getTracedMemory() struct { current: usize, peak: usize } {
    const state = getState();
    return .{
        .current = state.getTracedSize(),
        .peak = state.getPeakSize(),
    };
}

/// Reset peak memory tracker
pub fn resetPeak() void {
    getState().resetPeak();
}

/// Get traceback depth
pub fn getTracebackDepth() u32 {
    return getState().traceback_depth;
}

// ============================================================================
// Snapshot
// ============================================================================

/// Memory snapshot for comparison
pub const Snapshot = struct {
    allocations: std.ArrayList(struct { ptr: usize, size: usize }),
    timestamp: i64,
    traced_size: usize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocations = std.ArrayList(struct { ptr: usize, size: usize }).init(allocator),
            .timestamp = std.time.timestamp(),
            .traced_size = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocations.deinit();
    }
};

/// Take a snapshot of current allocations
pub fn takeSnapshot(allocator: Allocator) !Snapshot {
    var snapshot = Snapshot.init(allocator);
    const state = getState();

    state.mutex.lock();
    defer state.mutex.unlock();

    for (state.allocations) |bucket| {
        var current = bucket;
        while (current) |alloc| {
            try snapshot.allocations.append(.{
                .ptr = alloc.ptr,
                .size = alloc.size,
            });
            snapshot.traced_size += alloc.size;
            current = alloc.next;
        }
    }

    return snapshot;
}

// ============================================================================
// Domain Filtering
// ============================================================================

/// Memory domain constants
pub const Domain = struct {
    pub const DEFAULT: u32 = 0;
    pub const RAW: u32 = 1;
    pub const MEM: u32 = 2;
    pub const OBJECT: u32 = 3;
};

/// Set domain filter (0 = trace all)
pub fn setDomainFilter(domain: u32) void {
    getState().domain = domain;
}

/// Get domain filter
pub fn getDomainFilter() u32 {
    return getState().domain;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "tracemalloc basic" {
    var state = TracemallocState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expect(!state.isEnabled());

    state.start(10);
    try std.testing.expect(state.isEnabled());
    try std.testing.expectEqual(@as(u32, 10), state.traceback_depth);

    state.stop();
    try std.testing.expect(!state.isEnabled());
}

test "tracemalloc record alloc/free" {
    var state = TracemallocState.init(std.testing.allocator);
    defer state.deinit();

    state.start(10);

    state.recordAlloc(0x1000, 100);
    try std.testing.expectEqual(@as(usize, 1), state.stats.traced_count);
    try std.testing.expectEqual(@as(usize, 100), state.stats.traced_size);

    state.recordAlloc(0x2000, 200);
    try std.testing.expectEqual(@as(usize, 2), state.stats.traced_count);
    try std.testing.expectEqual(@as(usize, 300), state.stats.traced_size);

    state.recordFree(0x1000);
    try std.testing.expectEqual(@as(usize, 1), state.stats.traced_count);
    try std.testing.expectEqual(@as(usize, 200), state.stats.traced_size);

    state.clear();
    try std.testing.expectEqual(@as(usize, 0), state.stats.traced_count);
}

test "tracemalloc peak" {
    var state = TracemallocState.init(std.testing.allocator);
    defer state.deinit();

    state.start(10);

    state.recordAlloc(0x1000, 100);
    state.recordAlloc(0x2000, 200);
    try std.testing.expectEqual(@as(usize, 300), state.stats.peak_size);

    state.recordFree(0x2000);
    try std.testing.expectEqual(@as(usize, 300), state.stats.peak_size);
    try std.testing.expectEqual(@as(usize, 100), state.stats.traced_size);

    state.resetPeak();
    try std.testing.expectEqual(@as(usize, 100), state.stats.peak_size);
}

test "tracemalloc get allocation" {
    var state = TracemallocState.init(std.testing.allocator);
    defer state.deinit();

    state.start(10);

    state.recordAlloc(0x1000, 100);
    state.recordAlloc(0x2000, 200);

    const alloc = state.getAllocation(0x1000);
    try std.testing.expect(alloc != null);
    try std.testing.expectEqual(@as(usize, 100), alloc.?.size);

    const missing = state.getAllocation(0x3000);
    try std.testing.expect(missing == null);
}

test "snapshot" {
    var state = TracemallocState.init(std.testing.allocator);
    defer state.deinit();

    // Initialize global state for snapshot
    global_state = state;
    defer {
        global_state = null;
    }

    state.start(10);
    state.recordAlloc(0x1000, 100);
    state.recordAlloc(0x2000, 200);

    var snapshot = try takeSnapshot(std.testing.allocator);
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(usize, 2), snapshot.allocations.items.len);
    try std.testing.expectEqual(@as(usize, 300), snapshot.traced_size);
}

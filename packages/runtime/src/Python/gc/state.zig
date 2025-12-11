/// state - GC State
/// Global GC state and generation management.

const std = @import("std");
const types = @import("types.zig");

pub const GCHead = types.GCHead;
pub const Generation = types.Generation;
pub const GCCallback = types.GCCallback;
pub const GCStats = types.GCStats;

// ============================================================================
// GC State
// ============================================================================

/// Garbage collector state
pub const GCState = struct {
    /// Young generation (gen 0)
    young: Generation = .{},

    /// Old generations (for incremental collection)
    old: [2]Generation = .{ .{}, .{} },

    /// Permanent generation (never collected)
    permanent: Generation = .{},

    /// Which old space is being visited
    visited_space: u1 = 0,

    /// Is GC enabled?
    enabled: bool = true,

    /// Is a collection in progress?
    collecting: bool = false,

    /// Debug flags
    debug: u32 = 0,

    /// Number of allocations since last collection
    allocations: usize = 0,

    /// Total heap size (tracked objects)
    heap_size: usize = 0,

    /// Garbage list (objects with __del__ in cycles)
    garbage_count: usize = 0,

    /// Callbacks to run after collection
    callbacks: [8]?GCCallback = [_]?GCCallback{null} ** 8,
    callback_count: usize = 0,

    /// Collection statistics
    stats: GCStats = .{},

    const Self = @This();

    pub fn init(self: *Self) void {
        self.young.init();
        self.old[0].init();
        self.old[1].init();
        self.permanent.init();

        // Set default thresholds (matching CPython)
        self.young.threshold = 700;
        self.old[0].threshold = 10;
        self.old[1].threshold = 10;
    }

    pub fn getGeneration(self: *Self, n: u2) *Generation {
        return switch (n) {
            0 => &self.young,
            1 => &self.old[self.visited_space],
            2 => &self.old[self.visited_space ^ 1],
            3 => &self.permanent,
        };
    }
};

// ============================================================================
// Global GC State
// ============================================================================

/// Global GC state
pub var gc_state: GCState = .{};

/// Thread-local allocation counter
pub threadlocal var local_allocs: usize = 0;

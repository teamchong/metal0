/// types - Core GC types
/// Defines fundamental structures for GC with GIL

const std = @import("std");

// ============================================================================
// GC Configuration
// ============================================================================

/// GC thresholds per generation
pub const GCThresholds = struct {
    /// Generation 0 (young) threshold
    gen0: u32 = 700,
    /// Generation 1 threshold
    gen1: u32 = 10,
    /// Generation 2 (old) threshold
    gen2: u32 = 10,
};

/// GC flags
pub const GCFlags = packed struct {
    /// Object is tracked
    tracked: bool = false,
    /// Object is reachable
    reachable: bool = false,
    /// Object is a candidate for collection
    collecting: bool = false,
    /// Object has __del__ method
    has_legacy_finalizer: bool = false,
    /// Object's tp_finalize was called
    finalized: bool = false,
    /// Reserved
    _reserved: u3 = 0,
};

// ============================================================================
// GC Object Header
// ============================================================================

/// GC header prepended to container objects
pub const GCHead = struct {
    /// Pointer for doubly-linked list
    gc_next: ?*GCHead = null,
    gc_prev: ?*GCHead = null,
    /// Reference count adjustment for cycle detection
    gc_refs: i64 = 0,
    /// GC flags
    flags: GCFlags = .{},
    /// Generation
    generation: u8 = 0,

    /// Get the actual object pointer
    pub fn fromObject(obj: *anyopaque) *GCHead {
        return @as(*GCHead, @ptrFromInt(@intFromPtr(obj) - @sizeOf(GCHead)));
    }

    /// Get object from GC head
    pub fn toObject(self: *GCHead) *anyopaque {
        return @as(*anyopaque, @ptrFromInt(@intFromPtr(self) + @sizeOf(GCHead)));
    }
};

// ============================================================================
// Result Types
// ============================================================================

/// Collection result
pub const CollectResult = struct {
    collected: u64,
    uncollectable: u64,
};

/// GC statistics
pub const GCStats = struct {
    collections: [3]u64,
    collected: [3]u64,
    uncollectable: u64,
};

/// Debug flags
pub const GCDebugFlags = packed struct {
    stats: bool = false,
    collectable: bool = false,
    uncollectable: bool = false,
    saveall: bool = false,
    leak: bool = false,
    _reserved: u3 = 0,
};

// ============================================================================
// Tests
// ============================================================================

test "gc head operations" {
    var gc = GCHead{};
    try std.testing.expect(!gc.flags.tracked);

    gc.flags.tracked = true;
    try std.testing.expect(gc.flags.tracked);
}

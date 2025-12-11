/// generation - GC generation list management
/// Manages doubly-linked lists of objects per generation

const std = @import("std");
const types = @import("types.zig");
const GCHead = types.GCHead;

// ============================================================================
// Generation
// ============================================================================

/// GC generation list
pub const GCGeneration = struct {
    const Self = @This();

    /// List head (sentinel)
    head: GCHead = .{},
    /// Object count
    count: usize = 0,
    /// Collection count
    collections: u64 = 0,
    /// Objects collected
    collected: u64 = 0,
    /// Uncollectable (legacy finalizers)
    uncollectable: u64 = 0,

    pub fn initList(self: *Self) void {
        self.head.gc_next = &self.head;
        self.head.gc_prev = &self.head;
    }

    /// Add object to generation list
    pub fn add(self: *Self, gc: *GCHead) void {
        gc.gc_next = self.head.gc_next;
        gc.gc_prev = &self.head;
        if (self.head.gc_next) |next| {
            next.gc_prev = gc;
        }
        self.head.gc_next = gc;
        self.count += 1;
    }

    /// Remove object from list
    pub fn remove(self: *Self, gc: *GCHead) void {
        if (gc.gc_prev) |prev| {
            prev.gc_next = gc.gc_next;
        }
        if (gc.gc_next) |next| {
            next.gc_prev = gc.gc_prev;
        }
        gc.gc_next = null;
        gc.gc_prev = null;
        if (self.count > 0) {
            self.count -= 1;
        }
    }

    /// Check if list is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.head.gc_next == &self.head or self.count == 0;
    }

    /// Iterate over objects in generation
    pub fn iterator(self: *Self) Iterator {
        return Iterator{ .current = self.head.gc_next, .sentinel = &self.head };
    }

    pub const Iterator = struct {
        current: ?*GCHead,
        sentinel: *GCHead,

        pub fn next(self: *Iterator) ?*GCHead {
            if (self.current == self.sentinel or self.current == null) {
                return null;
            }
            const gc = self.current.?;
            self.current = gc.gc_next;
            return gc;
        }
    };
};

// ============================================================================
// Tests
// ============================================================================

test "generation list" {
    var gen = GCGeneration{};
    gen.initList();

    try std.testing.expect(gen.isEmpty());

    var gc1 = GCHead{};
    var gc2 = GCHead{};

    gen.add(&gc1);
    try std.testing.expectEqual(@as(usize, 1), gen.count);
    try std.testing.expect(!gen.isEmpty());

    gen.add(&gc2);
    try std.testing.expectEqual(@as(usize, 2), gen.count);

    gen.remove(&gc1);
    try std.testing.expectEqual(@as(usize, 1), gen.count);
}

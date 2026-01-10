//! test.test_ctypes.test_refcounts - Tests for reference counting
//! Reference: cpython/Lib/test/test_ctypes/test_refcounts.py
//!
//! Tests for reference counting behavior in ctypes.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Reference Counted Object
// ============================================================================

pub fn RefCounted(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        ref_count: usize = 1,
        weak_refs: usize = 0,

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        pub fn incref(self: *Self) void {
            self.ref_count +|= 1;
        }

        pub fn decref(self: *Self) bool {
            if (self.ref_count == 0) return true;
            self.ref_count -= 1;
            return self.ref_count == 0;
        }

        pub fn getRefCount(self: *const Self) usize {
            return self.ref_count;
        }

        pub fn addWeakRef(self: *Self) void {
            self.weak_refs += 1;
        }

        pub fn removeWeakRef(self: *Self) void {
            if (self.weak_refs > 0) {
                self.weak_refs -= 1;
            }
        }
    };
}

// ============================================================================
// Reference Counter
// ============================================================================

pub const RefCounter = struct {
    const Self = @This();
    const max_tracked = 64;

    counts: [max_tracked]usize = [_]usize{0} ** max_tracked,
    active: [max_tracked]bool = [_]bool{false} ** max_tracked,
    next_id: usize = 0,

    pub fn init() Self {
        return .{};
    }

    /// Allocate a new ID and set initial count
    pub fn alloc(self: *Self) !usize {
        for (0..max_tracked) |i| {
            if (!self.active[i]) {
                self.active[i] = true;
                self.counts[i] = 1;
                return i;
            }
        }
        return error.NoFreeSlots;
    }

    /// Increment reference count
    pub fn incref(self: *Self, id: usize) void {
        if (id < max_tracked and self.active[id]) {
            self.counts[id] +|= 1;
        }
    }

    /// Decrement reference count, returns true if freed
    pub fn decref(self: *Self, id: usize) bool {
        if (id < max_tracked and self.active[id]) {
            if (self.counts[id] > 0) {
                self.counts[id] -= 1;
            }
            if (self.counts[id] == 0) {
                self.active[id] = false;
                return true;
            }
        }
        return false;
    }

    /// Get current reference count
    pub fn getCount(self: *const Self, id: usize) ?usize {
        if (id < max_tracked and self.active[id]) {
            return self.counts[id];
        }
        return null;
    }

    /// Check if ID is still active
    pub fn isActive(self: *const Self, id: usize) bool {
        return id < max_tracked and self.active[id];
    }
};

// ============================================================================
// Reference Cycle Detection
// ============================================================================

pub fn CycleDetector(comptime max_nodes: usize) type {
    return struct {
        const Self = @This();

        edges: [max_nodes][max_nodes]bool = [_][max_nodes]bool{[_]bool{false} ** max_nodes} ** max_nodes,
        node_count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn addNode(self: *Self) !usize {
            if (self.node_count >= max_nodes) return error.TooManyNodes;
            const id = self.node_count;
            self.node_count += 1;
            return id;
        }

        pub fn addEdge(self: *Self, from: usize, to: usize) void {
            if (from < max_nodes and to < max_nodes) {
                self.edges[from][to] = true;
            }
        }

        /// Simple cycle detection using DFS
        pub fn hasCycle(self: *const Self) bool {
            var visited = [_]bool{false} ** max_nodes;
            var rec_stack = [_]bool{false} ** max_nodes;

            for (0..self.node_count) |i| {
                if (self.hasCycleDFS(i, &visited, &rec_stack)) {
                    return true;
                }
            }
            return false;
        }

        fn hasCycleDFS(self: *const Self, node: usize, visited: *[max_nodes]bool, rec_stack: *[max_nodes]bool) bool {
            if (rec_stack[node]) return true;
            if (visited[node]) return false;

            visited[node] = true;
            rec_stack[node] = true;

            for (0..self.node_count) |i| {
                if (self.edges[node][i] and self.hasCycleDFS(i, visited, rec_stack)) {
                    return true;
                }
            }

            rec_stack[node] = false;
            return false;
        }
    };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testRefCountedBasic() !void {
    var obj = RefCounted(i32).init(42);
    try std.testing.expectEqual(@as(usize, 1), obj.getRefCount());

    obj.incref();
    try std.testing.expectEqual(@as(usize, 2), obj.getRefCount());

    _ = obj.decref();
    try std.testing.expectEqual(@as(usize, 1), obj.getRefCount());

    const freed = obj.decref();
    try std.testing.expect(freed);
}

fn testRefCountedWeakRefs() !void {
    var obj = RefCounted(i32).init(100);

    obj.addWeakRef();
    obj.addWeakRef();
    try std.testing.expectEqual(@as(usize, 2), obj.weak_refs);

    obj.removeWeakRef();
    try std.testing.expectEqual(@as(usize, 1), obj.weak_refs);
}

fn testRefCounter() !void {
    var counter = RefCounter.init();

    const id = try counter.alloc();
    try std.testing.expectEqual(@as(?usize, 1), counter.getCount(id));

    counter.incref(id);
    try std.testing.expectEqual(@as(?usize, 2), counter.getCount(id));

    _ = counter.decref(id);
    try std.testing.expectEqual(@as(?usize, 1), counter.getCount(id));
}

fn testRefCounterFree() !void {
    var counter = RefCounter.init();

    const id = try counter.alloc();
    try std.testing.expect(counter.isActive(id));

    const freed = counter.decref(id);
    try std.testing.expect(freed);
    try std.testing.expect(!counter.isActive(id));
}

fn testRefCounterMultiple() !void {
    var counter = RefCounter.init();

    const id1 = try counter.alloc();
    const id2 = try counter.alloc();
    const id3 = try counter.alloc();

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);

    try std.testing.expect(counter.isActive(id1));
    try std.testing.expect(counter.isActive(id2));
    try std.testing.expect(counter.isActive(id3));

    _ = counter.decref(id2);
    try std.testing.expect(counter.isActive(id1));
    try std.testing.expect(!counter.isActive(id2));
    try std.testing.expect(counter.isActive(id3));
}

fn testCycleDetectorNoCycle() !void {
    var detector = CycleDetector(10).init();

    const n0 = try detector.addNode();
    const n1 = try detector.addNode();
    const n2 = try detector.addNode();

    detector.addEdge(n0, n1);
    detector.addEdge(n1, n2);

    try std.testing.expect(!detector.hasCycle());
}

fn testCycleDetectorWithCycle() !void {
    var detector = CycleDetector(10).init();

    const n0 = try detector.addNode();
    const n1 = try detector.addNode();
    const n2 = try detector.addNode();

    detector.addEdge(n0, n1);
    detector.addEdge(n1, n2);
    detector.addEdge(n2, n0); // Creates cycle

    try std.testing.expect(detector.hasCycle());
}

fn testCycleDetectorSelfCycle() !void {
    var detector = CycleDetector(10).init();

    const n0 = try detector.addNode();
    detector.addEdge(n0, n0); // Self-reference

    try std.testing.expect(detector.hasCycle());
}

fn testRefCounterSlotReuse() !void {
    var counter = RefCounter.init();

    const id1 = try counter.alloc();
    _ = counter.decref(id1);

    const id2 = try counter.alloc();
    try std.testing.expectEqual(id1, id2); // Should reuse slot
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "ref_counted_basic" {
    try testRefCountedBasic();
}

test "ref_counted_weak_refs" {
    try testRefCountedWeakRefs();
}

test "ref_counter" {
    try testRefCounter();
}

test "ref_counter_free" {
    try testRefCounterFree();
}

test "ref_counter_multiple" {
    try testRefCounterMultiple();
}

test "cycle_detector_no_cycle" {
    try testCycleDetectorNoCycle();
}

test "cycle_detector_with_cycle" {
    try testCycleDetectorWithCycle();
}

test "cycle_detector_self_cycle" {
    try testCycleDetectorSelfCycle();
}

test "ref_counter_slot_reuse" {
    try testRefCounterSlotReuse();
}

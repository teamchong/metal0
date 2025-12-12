/// graphlib - Graph algorithms
/// Mirrors cpython/Lib/graphlib.py (added in Python 3.9)
///
/// Provides topological sorting functionality for directed acyclic graphs.

const std = @import("std");

// ============================================================================
// Errors
// ============================================================================

pub const GraphError = error{
    CycleError,
    NodeNotFound,
    OutOfMemory,
};

// ============================================================================
// TopologicalSorter
// ============================================================================

/// Provides topological sorting of a graph of hashable nodes.
pub fn TopologicalSorter(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Adjacency list (node -> predecessors)
        graph: std.AutoHashMap(T, std.ArrayList(T)),
        /// All nodes in the graph
        nodes: std.AutoHashMap(T, void),
        /// Allocator
        allocator: std.mem.Allocator,
        /// Whether prepare() has been called
        prepared: bool = false,
        /// Current sorting state
        ready_nodes: std.ArrayList(T),
        /// Nodes that have been done
        done_nodes: std.AutoHashMap(T, void),
        /// In-degree count
        in_degree: std.AutoHashMap(T, usize),

        /// Create a new TopologicalSorter
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .graph = std.AutoHashMap(T, std.ArrayList(T)).init(allocator),
                .nodes = std.AutoHashMap(T, void).init(allocator),
                .allocator = allocator,
                .ready_nodes = .{},
                .done_nodes = std.AutoHashMap(T, void).init(allocator),
                .in_degree = std.AutoHashMap(T, usize).init(allocator),
            };
        }

        /// Deinitialize
        pub fn deinit(self: *Self) void {
            var it = self.graph.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            self.graph.deinit();
            self.nodes.deinit();
            self.ready_nodes.deinit(self.allocator);
            self.done_nodes.deinit();
            self.in_degree.deinit();
        }

        /// Add a node with its predecessors (dependencies)
        pub fn add(self: *Self, node: T, predecessors: anytype) !void {
            if (self.prepared) {
                return error.InvalidOperation;
            }

            // Add the node
            try self.nodes.put(node, {});

            // Get or create predecessor list
            const result = try self.graph.getOrPut(node);
            if (!result.found_existing) {
                result.value_ptr.* = .{};
            }

            // Add predecessors
            for (predecessors) |pred| {
                try result.value_ptr.append(self.allocator, pred);
                try self.nodes.put(pred, {});
            }
        }

        /// Prepare for iteration
        pub fn prepare(self: *Self) !void {
            if (self.prepared) return;

            // Calculate in-degrees
            var node_it = self.nodes.keyIterator();
            while (node_it.next()) |node| {
                try self.in_degree.put(node.*, 0);
            }

            var graph_it = self.graph.iterator();
            while (graph_it.next()) |entry| {
                for (entry.value_ptr.items) |pred| {
                    const current = self.in_degree.get(pred) orelse 0;
                    try self.in_degree.put(pred, current + 1);
                }
            }

            // Find initially ready nodes (in-degree 0)
            var degree_it = self.in_degree.iterator();
            while (degree_it.next()) |entry| {
                if (entry.value_ptr.* == 0) {
                    try self.ready_nodes.append(self.allocator, entry.key_ptr.*);
                }
            }

            self.prepared = true;
        }

        /// Check if sorting is active
        pub fn isActive(self: *const Self) bool {
            if (!self.prepared) return false;
            return self.done_nodes.count() < self.nodes.count();
        }

        /// Get the next batch of ready nodes
        pub fn getReady(self: *Self) ![]const T {
            if (!self.prepared) {
                try self.prepare();
            }

            return self.ready_nodes.items;
        }

        /// Mark nodes as done
        pub fn done(self: *Self, nodes_done: []const T) !void {
            if (!self.prepared) {
                try self.prepare();
            }

            self.ready_nodes.clearRetainingCapacity();

            for (nodes_done) |node| {
                try self.done_nodes.put(node, {});

                // Find successors and decrement their in-degree
                var graph_it = self.graph.iterator();
                while (graph_it.next()) |entry| {
                    for (entry.value_ptr.items) |pred| {
                        if (pred == node) {
                            const successor = entry.key_ptr.*;
                            const current = self.in_degree.get(successor) orelse 1;
                            if (current > 0) {
                                try self.in_degree.put(successor, current - 1);
                                if (current - 1 == 0 and !self.done_nodes.contains(successor)) {
                                    try self.ready_nodes.append(self.allocator, successor);
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Get a complete static order (all nodes sorted)
        pub fn staticOrder(self: *Self) ![]T {
            if (!self.prepared) {
                try self.prepare();
            }

            var result: std.ArrayList(T) = .{};
            errdefer result.deinit(self.allocator);

            while (self.isActive()) {
                const ready = try self.getReady();
                if (ready.len == 0) {
                    // Cycle detected
                    return GraphError.CycleError;
                }
                for (ready) |node| {
                    try result.append(self.allocator, node);
                }
                try self.done(ready);
            }

            return result.toOwnedSlice(self.allocator);
        }

        /// Copy the sorter
        pub fn copy(self: *const Self) !Self {
            var new_sorter = Self.init(self.allocator);

            // Copy graph
            var it = self.graph.iterator();
            while (it.next()) |entry| {
                var new_list: std.ArrayList(T) = .{};
                for (entry.value_ptr.items) |item| {
                    try new_list.append(self.allocator, item);
                }
                try new_sorter.graph.put(entry.key_ptr.*, new_list);
            }

            // Copy nodes
            var node_it = self.nodes.keyIterator();
            while (node_it.next()) |node| {
                try new_sorter.nodes.put(node.*, {});
            }

            return new_sorter;
        }
    };
}

// ============================================================================
// CycleError
// ============================================================================

/// Error info for cycle detection
pub fn CycleErrorInfo(comptime T: type) type {
    return struct {
        /// The cycle path
        cycle: []const T,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.cycle);
        }
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the graphlib module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "TopologicalSorter simple" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    // A depends on B and C
    // B depends on C
    try sorter.add(1, &[_]u32{ 2, 3 }); // A -> B, C
    try sorter.add(2, &[_]u32{3}); // B -> C
    try sorter.add(3, &[_]u32{}); // C has no deps

    const order = try sorter.staticOrder();
    defer allocator.free(order);

    // C should come before B, B before A
    try std.testing.expectEqual(@as(usize, 3), order.len);
}

test "TopologicalSorter getReady and done" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    try sorter.add(1, &[_]u32{2});
    try sorter.add(2, &[_]u32{});

    try sorter.prepare();

    // Node 2 should be ready first (no dependencies)
    const ready1 = try sorter.getReady();
    try std.testing.expect(ready1.len > 0);

    try sorter.done(ready1);

    // Now node 1 should be ready
    const ready2 = try sorter.getReady();
    try std.testing.expect(ready2.len > 0);
}

test "TopologicalSorter isActive" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    try sorter.add(1, &[_]u32{});

    try sorter.prepare();
    try std.testing.expect(sorter.isActive());

    const ready = try sorter.getReady();
    try sorter.done(ready);
    try std.testing.expect(!sorter.isActive());
}

test "TopologicalSorter copy" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    try sorter.add(1, &[_]u32{2});
    try sorter.add(2, &[_]u32{});

    var sorter_copy = try sorter.copy();
    defer sorter_copy.deinit();

    try std.testing.expectEqual(sorter.nodes.count(), sorter_copy.nodes.count());
}

test "TopologicalSorter empty" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    const order = try sorter.staticOrder();
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 0), order.len);
}

test "TopologicalSorter single node" {
    const allocator = std.testing.allocator;
    var sorter = TopologicalSorter(u32).init(allocator);
    defer sorter.deinit();

    try sorter.add(42, &[_]u32{});

    const order = try sorter.staticOrder();
    defer allocator.free(order);

    try std.testing.expectEqual(@as(usize, 1), order.len);
    try std.testing.expectEqual(@as(u32, 42), order[0]);
}

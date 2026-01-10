//! asyncio.graph - Task dependency graph for eager tasks
//! Reference: cpython/Lib/asyncio/graph.py
//! Python 3.12+ feature

const std = @import("std");

/// Topological sort for task ordering
/// Used by eager_task_factory
/// CPython: _bfs
pub fn topologicalSort(allocator: std.mem.Allocator, edges: []const [2]usize) ![]usize {
    if (edges.len == 0) {
        return &[_]usize{};
    }

    // Find all nodes
    var nodes = std.AutoHashMap(usize, void).init(allocator);
    defer nodes.deinit();

    for (edges) |edge| {
        try nodes.put(edge[0], {});
        try nodes.put(edge[1], {});
    }

    // Build adjacency list and in-degree count
    var adj = std.AutoHashMap(usize, std.ArrayList(usize)).init(allocator);
    defer {
        var it = adj.valueIterator();
        while (it.next()) |list| {
            list.deinit(allocator);
        }
        adj.deinit();
    }

    var in_degree = std.AutoHashMap(usize, usize).init(allocator);
    defer in_degree.deinit();

    for (edges) |edge| {
        const from = edge[0];
        const to = edge[1];

        if (!adj.contains(from)) {
            try adj.put(from, .{});
        }
        var list = adj.getPtr(from).?;
        try list.append(allocator, to);

        const current = in_degree.get(to) orelse 0;
        try in_degree.put(to, current + 1);
    }

    // BFS
    var queue: std.ArrayList(usize) = .{};
    defer queue.deinit(allocator);

    var result: std.ArrayList(usize) = .{};
    errdefer result.deinit(allocator);

    // Start with nodes having in-degree 0
    var node_it = nodes.keyIterator();
    while (node_it.next()) |node| {
        if ((in_degree.get(node.*) orelse 0) == 0) {
            try queue.append(allocator, node.*);
        }
    }

    while (queue.items.len > 0) {
        const node = queue.orderedRemove(0);
        try result.append(allocator, node);

        if (adj.get(node)) |neighbors| {
            for (neighbors.items) |neighbor| {
                const deg = in_degree.get(neighbor) orelse 1;
                if (deg > 0) {
                    try in_degree.put(neighbor, deg - 1);
                    if (deg - 1 == 0) {
                        try queue.append(allocator, neighbor);
                    }
                }
            }
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Check for cycles in dependency graph
pub fn hasCycle(allocator: std.mem.Allocator, edges: []const [2]usize) !bool {
    const sorted = try topologicalSort(allocator, edges);
    defer allocator.free(sorted);

    // Count unique nodes
    var nodes = std.AutoHashMap(usize, void).init(allocator);
    defer nodes.deinit();

    for (edges) |edge| {
        try nodes.put(edge[0], {});
        try nodes.put(edge[1], {});
    }

    return sorted.len != nodes.count();
}

// Tests
test "topologicalSort empty" {
    const allocator = std.testing.allocator;
    const result = try topologicalSort(allocator, &[_][2]usize{});
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "topologicalSort simple chain" {
    const allocator = std.testing.allocator;
    const edges = [_][2]usize{
        .{ 0, 1 },
        .{ 1, 2 },
    };
    const result = try topologicalSort(allocator, &edges);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

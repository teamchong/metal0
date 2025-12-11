/// dominators - Dominator Analysis
/// Mirrors cpython/Python/flowgraph.c - dominator computation
///
/// Computes dominator relationships for flow graphs.
/// A block X dominates Y if every path from entry to Y must go through X.

const std = @import("std");
const graph_mod = @import("graph.zig");

const FlowGraph = graph_mod.FlowGraph;
const BasicBlock = graph_mod.BasicBlock;

// ============================================================================
// Dominator Analysis
// ============================================================================

/// Compute dominators for flow graph
pub fn computeDominators(graph: *FlowGraph) !void {
    if (graph.entry == null) return;

    // Initialize dominators
    for (graph.blocks.items) |blk| {
        if (blk.dominators == null) {
            blk.dominators = .{};
        } else {
            blk.dominators.?.clearRetainingCapacity();
        }

        // Entry block only dominates itself
        if (blk == graph.entry) {
            try blk.dominators.?.append(graph.allocator, blk);
        } else {
            // All others initially dominated by all blocks
            for (graph.blocks.items) |b| {
                try blk.dominators.?.append(graph.allocator, b);
            }
        }
    }

    // Iterate until fixed point
    var changed = true;
    while (changed) {
        changed = false;

        for (graph.blocks.items) |blk| {
            if (blk == graph.entry) continue;
            if (blk.predecessors.items.len == 0) continue;

            // New dominators = intersection of predecessors' dominators + self
            var new_doms: std.ArrayList(*BasicBlock) = .{};
            defer new_doms.deinit(graph.allocator);

            // Start with first predecessor's dominators
            if (blk.predecessors.items[0].dominators) |pred_doms| {
                for (pred_doms.items) |d| {
                    try new_doms.append(graph.allocator, d);
                }
            }

            // Intersect with other predecessors
            for (blk.predecessors.items[1..]) |pred| {
                if (pred.dominators) |pred_doms| {
                    var i: usize = 0;
                    while (i < new_doms.items.len) {
                        var found = false;
                        for (pred_doms.items) |d| {
                            if (d == new_doms.items[i]) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            _ = new_doms.orderedRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            // Add self
            var has_self = false;
            for (new_doms.items) |d| {
                if (d == blk) {
                    has_self = true;
                    break;
                }
            }
            if (!has_self) {
                try new_doms.append(graph.allocator, blk);
            }

            // Check if changed
            if (new_doms.items.len != blk.dominators.?.items.len) {
                changed = true;
                blk.dominators.?.clearRetainingCapacity();
                for (new_doms.items) |d| {
                    try blk.dominators.?.append(graph.allocator, d);
                }
            }
        }
    }
}

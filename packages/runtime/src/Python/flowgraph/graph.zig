/// graph - Control Flow Graph
/// Mirrors cpython/Python/flowgraph.c - CFG construction and analysis
///
/// The flow graph represents the control flow of a function as a graph of
/// basic blocks. It's used for optimization passes and bytecode generation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const block = @import("block.zig");

pub const BasicBlock = block.BasicBlock;

// ============================================================================
// Control Flow Graph
// ============================================================================

/// Control flow graph for a function
pub const FlowGraph = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// All basic blocks
    blocks: std.ArrayList(*BasicBlock),
    /// Entry block
    entry: ?*BasicBlock = null,
    /// Exit blocks
    exits: std.ArrayList(*BasicBlock),
    /// Block ID counter
    next_id: u32 = 0,
    /// Maximum stack depth
    max_stack_depth: i32 = 0,
    /// Has been analyzed
    analyzed: bool = false,

    /// Create a new flow graph
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .blocks = .{},
            .exits = .{},
        };
    }

    /// Free flow graph resources
    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |blk| {
            blk.deinit();
            self.allocator.destroy(blk);
        }
        self.blocks.deinit(self.allocator);
        self.exits.deinit(self.allocator);
    }

    /// Create a new basic block
    pub fn newBlock(self: *Self) !*BasicBlock {
        const blk = try self.allocator.create(BasicBlock);
        blk.* = BasicBlock.init(self.allocator, self.next_id);
        self.next_id += 1;
        try self.blocks.append(self.allocator, blk);
        return blk;
    }

    /// Set entry block
    pub fn setEntry(self: *Self, blk: *BasicBlock) void {
        self.entry = blk;
    }

    /// Add exit block
    pub fn addExit(self: *Self, blk: *BasicBlock) !void {
        for (self.exits.items) |e| {
            if (e == blk) return;
        }
        try self.exits.append(self.allocator, blk);
    }

    /// Mark reachable blocks using DFS
    pub fn markReachable(self: *Self) void {
        // Reset all blocks
        for (self.blocks.items) |blk| {
            blk.reachable = false;
            blk.visited = false;
        }

        if (self.entry) |entry| {
            self.markReachableFrom(entry);
        }
    }

    fn markReachableFrom(self: *Self, blk: *BasicBlock) void {
        if (blk.visited) return;
        blk.visited = true;
        blk.reachable = true;

        for (blk.successors.items) |succ| {
            self.markReachableFrom(succ);
        }
    }

    /// Remove unreachable blocks
    pub fn removeUnreachable(self: *Self) void {
        self.markReachable();

        var i: usize = 0;
        while (i < self.blocks.items.len) {
            const blk = self.blocks.items[i];
            if (!blk.reachable) {
                // Remove edges
                for (blk.successors.items) |succ| {
                    blk.removeSuccessor(succ);
                }

                // Free and remove
                blk.deinit();
                self.allocator.destroy(blk);
                _ = self.blocks.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Calculate stack depths for all blocks
    pub fn calculateStackDepths(self: *Self) !void {
        if (self.entry == null) return;

        // Reset
        for (self.blocks.items) |blk| {
            blk.entry_stack_depth = -1;
            blk.exit_stack_depth = -1;
            blk.visited = false;
        }

        // BFS from entry
        var worklist: std.ArrayList(*BasicBlock) = .{};
        defer worklist.deinit(self.allocator);

        self.entry.?.entry_stack_depth = 0;
        try worklist.append(self.allocator, self.entry.?);

        while (worklist.items.len > 0) {
            const blk = worklist.orderedRemove(0);
            if (blk.visited) continue;
            blk.visited = true;

            const exit_depth = blk.calculateStackDepth(blk.entry_stack_depth);
            if (exit_depth > self.max_stack_depth) {
                self.max_stack_depth = exit_depth;
            }

            // Propagate to successors
            for (blk.successors.items) |succ| {
                if (succ.entry_stack_depth < 0) {
                    succ.entry_stack_depth = exit_depth;
                    try worklist.append(self.allocator, succ);
                } else if (succ.entry_stack_depth != exit_depth) {
                    // Stack depth mismatch - error in bytecode
                    return error.StackDepthMismatch;
                }
            }
        }
    }

    /// Detect loops using DFS with back edges
    pub fn detectLoops(self: *Self) void {
        for (self.blocks.items) |blk| {
            blk.visited = false;
            blk.loop_header = null;
            blk.loop_depth = 0;
        }

        if (self.entry) |entry| {
            self.detectLoopsFrom(entry, 0);
        }
    }

    fn detectLoopsFrom(self: *Self, blk: *BasicBlock, depth: u32) void {
        if (blk.visited) {
            // Back edge - this is a loop header
            blk.loop_header = blk;
            return;
        }

        blk.visited = true;
        blk.loop_depth = depth;

        for (blk.successors.items) |succ| {
            self.detectLoopsFrom(succ, depth);
            if (succ.loop_header) |header| {
                if (blk.loop_header == null) {
                    blk.loop_header = header;
                    blk.loop_depth = depth + 1;
                }
            }
        }
    }

    /// Merge consecutive blocks with single edge
    pub fn mergeBlocks(self: *Self) void {
        var changed = true;
        while (changed) {
            changed = false;
            for (self.blocks.items) |blk| {
                // Can merge if:
                // 1. Block has single successor
                // 2. Successor has single predecessor (this block)
                // 3. Block doesn't end with conditional jump
                if (blk.successors.items.len == 1) {
                    const succ = blk.successors.items[0];
                    if (succ.predecessors.items.len == 1 and
                        !blk.endsWithUnconditionalJump())
                    {
                        // Merge succ into block
                        for (succ.instructions.items) |instr| {
                            blk.instructions.append(blk.allocator, instr) catch continue;
                        }

                        // Update edges
                        blk.successors.clearRetainingCapacity();
                        for (succ.successors.items) |new_succ| {
                            blk.addSuccessor(new_succ) catch continue;
                        }

                        // Mark succ as unreachable
                        succ.reachable = false;
                        changed = true;
                    }
                }
            }
        }

        self.removeUnreachable();
    }

    /// Perform all analysis passes
    pub fn analyze(self: *Self) !void {
        self.markReachable();
        self.removeUnreachable();
        try self.calculateStackDepths();
        self.detectLoops();
        self.analyzed = true;
    }
};

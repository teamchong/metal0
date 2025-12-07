/// flowgraph - Control Flow Graph
/// Mirrors cpython/Python/flowgraph.c
///
/// The flow graph represents the control flow of a function as a graph of
/// basic blocks. It's used for optimization passes and bytecode generation.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Basic Block Types
// ============================================================================

/// A basic block contains a sequence of instructions with a single entry
/// and exit point. Control flow only branches at the end of a block.
pub const BasicBlock = struct {
    const Self = @This();

    /// Block identifier
    id: u32,
    /// Instructions in this block
    instructions: std.ArrayList(Instruction),
    /// Successors (next blocks in control flow)
    successors: std.ArrayList(*Self),
    /// Predecessors (blocks that jump here)
    predecessors: std.ArrayList(*Self),
    /// Block is reachable from entry
    reachable: bool = false,
    /// Block has been visited (for graph traversal)
    visited: bool = false,
    /// Stack depth at block entry
    entry_stack_depth: i32 = -1,
    /// Stack depth at block exit
    exit_stack_depth: i32 = -1,
    /// Line number of first instruction
    start_line: i32 = 0,
    /// Exception handler block (if in try block)
    except_handler: ?*Self = null,
    /// Finally block (if in try-finally)
    finally_handler: ?*Self = null,
    /// Dominators (blocks that dominate this one)
    dominators: ?std.ArrayList(*Self) = null,
    /// Immediate dominator
    idom: ?*Self = null,
    /// Blocks this one dominates
    dominated: ?std.ArrayList(*Self) = null,
    /// Loop header if in a loop
    loop_header: ?*Self = null,
    /// Loop depth (0 = not in loop)
    loop_depth: u32 = 0,

    /// Memory allocator
    allocator: Allocator,

    /// Create a new basic block
    pub fn init(allocator: Allocator, id: u32) Self {
        return Self{
            .id = id,
            .instructions = std.ArrayList(Instruction).init(allocator),
            .successors = std.ArrayList(*Self).init(allocator),
            .predecessors = std.ArrayList(*Self).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free basic block resources
    pub fn deinit(self: *Self) void {
        self.instructions.deinit();
        self.successors.deinit();
        self.predecessors.deinit();
        if (self.dominators) |*d| d.deinit();
        if (self.dominated) |*d| d.deinit();
    }

    /// Add instruction to block
    pub fn addInstruction(self: *Self, instr: Instruction) !void {
        try self.instructions.append(instr);
    }

    /// Add successor edge
    pub fn addSuccessor(self: *Self, succ: *Self) !void {
        // Avoid duplicates
        for (self.successors.items) |s| {
            if (s == succ) return;
        }
        try self.successors.append(succ);
        try succ.predecessors.append(self);
    }

    /// Remove successor edge
    pub fn removeSuccessor(self: *Self, succ: *Self) void {
        // Remove from successors
        var i: usize = 0;
        while (i < self.successors.items.len) {
            if (self.successors.items[i] == succ) {
                _ = self.successors.orderedRemove(i);
            } else {
                i += 1;
            }
        }

        // Remove from predecessor's predecessors
        i = 0;
        while (i < succ.predecessors.items.len) {
            if (succ.predecessors.items[i] == self) {
                _ = succ.predecessors.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Check if block is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.instructions.items.len == 0;
    }

    /// Get last instruction
    pub fn lastInstruction(self: *Self) ?*Instruction {
        if (self.instructions.items.len == 0) return null;
        return &self.instructions.items[self.instructions.items.len - 1];
    }

    /// Check if block ends with unconditional jump
    pub fn endsWithUnconditionalJump(self: *Self) bool {
        if (self.lastInstruction()) |instr| {
            return instr.isUnconditionalJump();
        }
        return false;
    }

    /// Check if block ends with return
    pub fn endsWithReturn(self: *Self) bool {
        if (self.lastInstruction()) |instr| {
            return instr.opcode == .RETURN_VALUE or instr.opcode == .RETURN_CONST;
        }
        return false;
    }

    /// Calculate stack depth through block
    pub fn calculateStackDepth(self: *Self, entry_depth: i32) i32 {
        self.entry_stack_depth = entry_depth;
        var depth = entry_depth;

        for (self.instructions.items) |instr| {
            depth += instr.stackEffect();
        }

        self.exit_stack_depth = depth;
        return depth;
    }
};

/// Instruction in basic block
pub const Instruction = struct {
    /// Opcode
    opcode: Opcode,
    /// Argument
    arg: u32 = 0,
    /// Source line number
    lineno: i32 = 0,
    /// Column offset
    col_offset: i32 = 0,
    /// End line number
    end_lineno: i32 = 0,
    /// End column offset
    end_col_offset: i32 = 0,
    /// Jump target block
    target: ?*BasicBlock = null,

    /// Check if instruction is unconditional jump
    pub fn isUnconditionalJump(self: *const Instruction) bool {
        return self.opcode == .JUMP_FORWARD or
            self.opcode == .JUMP_BACKWARD or
            self.opcode == .JUMP_BACKWARD_NO_INTERRUPT;
    }

    /// Check if instruction is conditional jump
    pub fn isConditionalJump(self: *const Instruction) bool {
        return self.opcode == .POP_JUMP_IF_FALSE or
            self.opcode == .POP_JUMP_IF_TRUE or
            self.opcode == .JUMP_IF_FALSE_OR_POP or
            self.opcode == .JUMP_IF_TRUE_OR_POP or
            self.opcode == .FOR_ITER;
    }

    /// Check if instruction is any jump
    pub fn isJump(self: *const Instruction) bool {
        return self.isUnconditionalJump() or self.isConditionalJump();
    }

    /// Get stack effect
    pub fn stackEffect(self: *const Instruction) i32 {
        return switch (self.opcode) {
            .NOP => 0,
            .POP_TOP => -1,
            .PUSH_NULL => 1,
            .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
            .BINARY_OP, .BINARY_SUBSCR, .COMPARE_OP => -1,
            .STORE_SUBSCR => -3,
            .DELETE_SUBSCR => -2,
            .RETURN_VALUE => -1,
            .RETURN_CONST => 0,
            .LOAD_CONST, .LOAD_NAME, .LOAD_FAST, .LOAD_GLOBAL, .LOAD_DEREF => 1,
            .STORE_NAME, .STORE_FAST, .STORE_GLOBAL, .STORE_DEREF => -1,
            .STORE_ATTR => -2,
            .DELETE_ATTR => -1,
            .LOAD_ATTR => 0,
            .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => -1,
            .JUMP_IF_FALSE_OR_POP, .JUMP_IF_TRUE_OR_POP => 0,
            .JUMP_FORWARD, .JUMP_BACKWARD, .JUMP_BACKWARD_NO_INTERRUPT => 0,
            .FOR_ITER => 1,
            .GET_ITER => 0,
            .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => 1 - @as(i32, @intCast(self.arg)),
            .BUILD_MAP => 1 - @as(i32, @intCast(2 * self.arg)),
            .CALL => -@as(i32, @intCast(self.arg)) - 1,
            else => 0,
        };
    }
};

/// Opcodes
pub const Opcode = enum(u8) {
    NOP = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,
    END_FOR = 4,

    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    BINARY_OP = 22,
    BINARY_SUBSCR = 25,

    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    GET_ITER = 68,

    RETURN_VALUE = 83,
    RETURN_CONST = 121,

    STORE_NAME = 90,
    DELETE_NAME = 91,
    FOR_ITER = 93,

    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,

    LOAD_CONST = 100,
    LOAD_NAME = 101,
    BUILD_TUPLE = 102,
    BUILD_LIST = 103,
    BUILD_SET = 104,
    BUILD_MAP = 105,
    LOAD_ATTR = 106,
    COMPARE_OP = 107,

    JUMP_FORWARD = 110,
    JUMP_IF_FALSE_OR_POP = 111,
    JUMP_IF_TRUE_OR_POP = 112,
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,

    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,

    JUMP_BACKWARD_NO_INTERRUPT = 134,
    LOAD_DEREF = 137,
    STORE_DEREF = 138,
    DELETE_DEREF = 139,
    JUMP_BACKWARD = 140,

    CALL = 171,
};

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
            .blocks = std.ArrayList(*BasicBlock).init(allocator),
            .exits = std.ArrayList(*BasicBlock).init(allocator),
        };
    }

    /// Free flow graph resources
    pub fn deinit(self: *Self) void {
        for (self.blocks.items) |block| {
            block.deinit();
            self.allocator.destroy(block);
        }
        self.blocks.deinit();
        self.exits.deinit();
    }

    /// Create a new basic block
    pub fn newBlock(self: *Self) !*BasicBlock {
        const block = try self.allocator.create(BasicBlock);
        block.* = BasicBlock.init(self.allocator, self.next_id);
        self.next_id += 1;
        try self.blocks.append(block);
        return block;
    }

    /// Set entry block
    pub fn setEntry(self: *Self, block: *BasicBlock) void {
        self.entry = block;
    }

    /// Add exit block
    pub fn addExit(self: *Self, block: *BasicBlock) !void {
        for (self.exits.items) |e| {
            if (e == block) return;
        }
        try self.exits.append(block);
    }

    /// Mark reachable blocks using DFS
    pub fn markReachable(self: *Self) void {
        // Reset all blocks
        for (self.blocks.items) |block| {
            block.reachable = false;
            block.visited = false;
        }

        if (self.entry) |entry| {
            self.markReachableFrom(entry);
        }
    }

    fn markReachableFrom(self: *Self, block: *BasicBlock) void {
        if (block.visited) return;
        block.visited = true;
        block.reachable = true;

        for (block.successors.items) |succ| {
            self.markReachableFrom(succ);
        }
    }

    /// Remove unreachable blocks
    pub fn removeUnreachable(self: *Self) void {
        self.markReachable();

        var i: usize = 0;
        while (i < self.blocks.items.len) {
            const block = self.blocks.items[i];
            if (!block.reachable) {
                // Remove edges
                for (block.successors.items) |succ| {
                    block.removeSuccessor(succ);
                }

                // Free and remove
                block.deinit();
                self.allocator.destroy(block);
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
        for (self.blocks.items) |block| {
            block.entry_stack_depth = -1;
            block.exit_stack_depth = -1;
            block.visited = false;
        }

        // BFS from entry
        var worklist = std.ArrayList(*BasicBlock).init(self.allocator);
        defer worklist.deinit();

        self.entry.?.entry_stack_depth = 0;
        try worklist.append(self.entry.?);

        while (worklist.items.len > 0) {
            const block = worklist.orderedRemove(0);
            if (block.visited) continue;
            block.visited = true;

            const exit_depth = block.calculateStackDepth(block.entry_stack_depth);
            if (exit_depth > self.max_stack_depth) {
                self.max_stack_depth = exit_depth;
            }

            // Propagate to successors
            for (block.successors.items) |succ| {
                if (succ.entry_stack_depth < 0) {
                    succ.entry_stack_depth = exit_depth;
                    try worklist.append(succ);
                } else if (succ.entry_stack_depth != exit_depth) {
                    // Stack depth mismatch - error in bytecode
                    return error.StackDepthMismatch;
                }
            }
        }
    }

    /// Detect loops using DFS with back edges
    pub fn detectLoops(self: *Self) void {
        for (self.blocks.items) |block| {
            block.visited = false;
            block.loop_header = null;
            block.loop_depth = 0;
        }

        if (self.entry) |entry| {
            self.detectLoopsFrom(entry, 0);
        }
    }

    fn detectLoopsFrom(self: *Self, block: *BasicBlock, depth: u32) void {
        if (block.visited) {
            // Back edge - this is a loop header
            block.loop_header = block;
            return;
        }

        block.visited = true;
        block.loop_depth = depth;

        for (block.successors.items) |succ| {
            self.detectLoopsFrom(succ, depth);
            if (succ.loop_header) |header| {
                if (block.loop_header == null) {
                    block.loop_header = header;
                    block.loop_depth = depth + 1;
                }
            }
        }
    }

    /// Merge consecutive blocks with single edge
    pub fn mergeBlocks(self: *Self) void {
        var changed = true;
        while (changed) {
            changed = false;
            for (self.blocks.items) |block| {
                // Can merge if:
                // 1. Block has single successor
                // 2. Successor has single predecessor (this block)
                // 3. Block doesn't end with conditional jump
                if (block.successors.items.len == 1) {
                    const succ = block.successors.items[0];
                    if (succ.predecessors.items.len == 1 and
                        !block.endsWithUnconditionalJump())
                    {
                        // Merge succ into block
                        for (succ.instructions.items) |instr| {
                            block.instructions.append(instr) catch continue;
                        }

                        // Update edges
                        block.successors.clearRetainingCapacity();
                        for (succ.successors.items) |new_succ| {
                            block.addSuccessor(new_succ) catch continue;
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

// ============================================================================
// Dominator Analysis
// ============================================================================

/// Compute dominators for flow graph
pub fn computeDominators(graph: *FlowGraph) !void {
    if (graph.entry == null) return;

    // Initialize dominators
    for (graph.blocks.items) |block| {
        if (block.dominators == null) {
            block.dominators = std.ArrayList(*BasicBlock).init(graph.allocator);
        } else {
            block.dominators.?.clearRetainingCapacity();
        }

        // Entry block only dominates itself
        if (block == graph.entry) {
            try block.dominators.?.append(block);
        } else {
            // All others initially dominated by all blocks
            for (graph.blocks.items) |b| {
                try block.dominators.?.append(b);
            }
        }
    }

    // Iterate until fixed point
    var changed = true;
    while (changed) {
        changed = false;

        for (graph.blocks.items) |block| {
            if (block == graph.entry) continue;
            if (block.predecessors.items.len == 0) continue;

            // New dominators = intersection of predecessors' dominators + self
            var new_doms = std.ArrayList(*BasicBlock).init(graph.allocator);
            defer new_doms.deinit();

            // Start with first predecessor's dominators
            if (block.predecessors.items[0].dominators) |pred_doms| {
                for (pred_doms.items) |d| {
                    try new_doms.append(d);
                }
            }

            // Intersect with other predecessors
            for (block.predecessors.items[1..]) |pred| {
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
                if (d == block) {
                    has_self = true;
                    break;
                }
            }
            if (!has_self) {
                try new_doms.append(block);
            }

            // Check if changed
            if (new_doms.items.len != block.dominators.?.items.len) {
                changed = true;
                block.dominators.?.clearRetainingCapacity();
                for (new_doms.items) |d| {
                    try block.dominators.?.append(d);
                }
            }
        }
    }
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the flowgraph module
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

test "basic block creation" {
    const allocator = std.testing.allocator;

    var graph = FlowGraph.init(allocator);
    defer graph.deinit();

    const b1 = try graph.newBlock();
    const b2 = try graph.newBlock();

    try std.testing.expectEqual(@as(u32, 0), b1.id);
    try std.testing.expectEqual(@as(u32, 1), b2.id);
}

test "block edges" {
    const allocator = std.testing.allocator;

    var graph = FlowGraph.init(allocator);
    defer graph.deinit();

    const b1 = try graph.newBlock();
    const b2 = try graph.newBlock();
    const b3 = try graph.newBlock();

    try b1.addSuccessor(b2);
    try b1.addSuccessor(b3);

    try std.testing.expectEqual(@as(usize, 2), b1.successors.items.len);
    try std.testing.expectEqual(@as(usize, 1), b2.predecessors.items.len);
    try std.testing.expectEqual(@as(usize, 1), b3.predecessors.items.len);
}

test "reachability" {
    const allocator = std.testing.allocator;

    var graph = FlowGraph.init(allocator);
    defer graph.deinit();

    const b1 = try graph.newBlock();
    const b2 = try graph.newBlock();
    const b3 = try graph.newBlock(); // Unreachable

    graph.setEntry(b1);
    try b1.addSuccessor(b2);
    // b3 has no edges - unreachable

    graph.markReachable();

    try std.testing.expect(b1.reachable);
    try std.testing.expect(b2.reachable);
    try std.testing.expect(!b3.reachable);
}

test "stack depth calculation" {
    const allocator = std.testing.allocator;

    var graph = FlowGraph.init(allocator);
    defer graph.deinit();

    const b1 = try graph.newBlock();
    graph.setEntry(b1);

    try b1.addInstruction(.{ .opcode = .LOAD_CONST, .arg = 0 });
    try b1.addInstruction(.{ .opcode = .LOAD_CONST, .arg = 1 });
    try b1.addInstruction(.{ .opcode = .BINARY_OP, .arg = 0 });
    try b1.addInstruction(.{ .opcode = .RETURN_VALUE });

    try graph.calculateStackDepths();

    try std.testing.expectEqual(@as(i32, 0), b1.entry_stack_depth);
    try std.testing.expectEqual(@as(i32, 0), b1.exit_stack_depth); // 0 + 1 + 1 - 1 - 1 = 0
    try std.testing.expectEqual(@as(i32, 2), graph.max_stack_depth);
}

test "instruction stack effects" {
    const load = Instruction{ .opcode = .LOAD_CONST };
    const pop = Instruction{ .opcode = .POP_TOP };
    const binary = Instruction{ .opcode = .BINARY_OP };
    const build_tuple = Instruction{ .opcode = .BUILD_TUPLE, .arg = 3 };

    try std.testing.expectEqual(@as(i32, 1), load.stackEffect());
    try std.testing.expectEqual(@as(i32, -1), pop.stackEffect());
    try std.testing.expectEqual(@as(i32, -1), binary.stackEffect());
    try std.testing.expectEqual(@as(i32, -2), build_tuple.stackEffect()); // 1 - 3
}

test "loop detection" {
    const allocator = std.testing.allocator;

    var graph = FlowGraph.init(allocator);
    defer graph.deinit();

    const entry = try graph.newBlock();
    const loop_body = try graph.newBlock();
    const exit = try graph.newBlock();

    graph.setEntry(entry);
    try entry.addSuccessor(loop_body);
    try loop_body.addSuccessor(loop_body); // Back edge
    try loop_body.addSuccessor(exit);

    graph.detectLoops();

    try std.testing.expect(loop_body.loop_header != null);
}

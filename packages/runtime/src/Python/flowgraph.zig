/// flowgraph - Control Flow Graph
/// Mirrors cpython/Python/flowgraph.c
///
/// The flow graph represents the control flow of a function as a graph of
/// basic blocks. It's used for optimization passes and bytecode generation.

// Re-export all submodules
pub const block = @import("flowgraph/block.zig");
pub const graph = @import("flowgraph/graph.zig");
pub const dominators = @import("flowgraph/dominators.zig");

// Re-export commonly used types
pub const BasicBlock = block.BasicBlock;
pub const Instruction = block.Instruction;
pub const Opcode = block.Opcode;
pub const FlowGraph = graph.FlowGraph;
pub const computeDominators = dominators.computeDominators;

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

const std = @import("std");

test "basic block creation" {
    const allocator = std.testing.allocator;

    var fg = FlowGraph.init(allocator);
    defer fg.deinit();

    const b1 = try fg.newBlock();
    const b2 = try fg.newBlock();

    try std.testing.expectEqual(@as(u32, 0), b1.id);
    try std.testing.expectEqual(@as(u32, 1), b2.id);
}

test "block edges" {
    const allocator = std.testing.allocator;

    var fg = FlowGraph.init(allocator);
    defer fg.deinit();

    const b1 = try fg.newBlock();
    const b2 = try fg.newBlock();
    const b3 = try fg.newBlock();

    try b1.addSuccessor(b2);
    try b1.addSuccessor(b3);

    try std.testing.expectEqual(@as(usize, 2), b1.successors.items.len);
    try std.testing.expectEqual(@as(usize, 1), b2.predecessors.items.len);
    try std.testing.expectEqual(@as(usize, 1), b3.predecessors.items.len);
}

test "reachability" {
    const allocator = std.testing.allocator;

    var fg = FlowGraph.init(allocator);
    defer fg.deinit();

    const b1 = try fg.newBlock();
    const b2 = try fg.newBlock();
    const b3 = try fg.newBlock(); // Unreachable

    fg.setEntry(b1);
    try b1.addSuccessor(b2);
    // b3 has no edges - unreachable

    fg.markReachable();

    try std.testing.expect(b1.reachable);
    try std.testing.expect(b2.reachable);
    try std.testing.expect(!b3.reachable);
}

test "stack depth calculation" {
    const allocator = std.testing.allocator;

    var fg = FlowGraph.init(allocator);
    defer fg.deinit();

    const b1 = try fg.newBlock();
    fg.setEntry(b1);

    try b1.addInstruction(.{ .opcode = .LOAD_CONST, .arg = 0 });
    try b1.addInstruction(.{ .opcode = .LOAD_CONST, .arg = 1 });
    try b1.addInstruction(.{ .opcode = .BINARY_OP, .arg = 0 });
    try b1.addInstruction(.{ .opcode = .RETURN_VALUE });

    try fg.calculateStackDepths();

    try std.testing.expectEqual(@as(i32, 0), b1.entry_stack_depth);
    try std.testing.expectEqual(@as(i32, 0), b1.exit_stack_depth); // 0 + 1 + 1 - 1 - 1 = 0
    try std.testing.expectEqual(@as(i32, 2), fg.max_stack_depth);
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

    var fg = FlowGraph.init(allocator);
    defer fg.deinit();

    const entry = try fg.newBlock();
    const loop_body = try fg.newBlock();
    const exit = try fg.newBlock();

    fg.setEntry(entry);
    try entry.addSuccessor(loop_body);
    try loop_body.addSuccessor(loop_body); // Back edge
    try loop_body.addSuccessor(exit);

    fg.detectLoops();

    try std.testing.expect(loop_body.loop_header != null);
}

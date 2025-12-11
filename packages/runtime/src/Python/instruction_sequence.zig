/// instruction_sequence - Instruction Sequence
/// Mirrors cpython/Python/instruction_sequence.c
///
/// Manages sequences of bytecode instructions during compilation.
/// Provides builder pattern for constructing bytecode with labels and jumps.

const std = @import("std");
const types = @import("instruction_sequence/types.zig");
const sequence = @import("instruction_sequence/sequence.zig");
const stack_effects = @import("instruction_sequence/stack_effects.zig");
const line_table = @import("instruction_sequence/line_table.zig");
const module_state = @import("instruction_sequence/module_state.zig");

// Re-export types
pub const Instruction = types.Instruction;
pub const LabelId = types.LabelId;
pub const LABEL_NONE = types.LABEL_NONE;
pub const Label = types.Label;
pub const ExceptionHandler = types.ExceptionHandler;
pub const Opcode = types.Opcode;

// Re-export InstructionSequence
pub const InstructionSequence = sequence.InstructionSequence;

// Re-export stack effects
pub const getStackEffect = stack_effects.getStackEffect;

// Re-export LineNumberTable
pub const LineNumberTable = line_table.LineNumberTable;

// Re-export module state
pub const init = module_state.init;
pub const reset = module_state.reset;

// ============================================================================
// Tests
// ============================================================================

test "instruction struct" {
    const inst = Instruction{
        .opcode = Opcode.LOAD_CONST,
        .arg = 42,
        .lineno = 10,
    };
    try std.testing.expectEqual(@as(u8, 1), inst.opcode);
    try std.testing.expectEqual(@as(u32, 42), inst.arg);
}

test "instruction sequence basic" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 1);
    try seq.addOpArg(Opcode.LOAD_CONST, 2);
    try seq.addOpArg(Opcode.BINARY_ADD, 0);
    try seq.addOp(Opcode.RETURN_VALUE);

    try std.testing.expectEqual(@as(usize, 4), seq.length());
}

test "label creation and placement" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    const label = try seq.newLabel();
    try seq.addOpArg(Opcode.LOAD_CONST, 0);
    try seq.placeLabel(label);
    try seq.addOp(Opcode.RETURN_VALUE);

    const placed_label = seq.labels.get(label);
    try std.testing.expect(placed_label != null);
    try std.testing.expect(placed_label.?.placed);
    try std.testing.expectEqual(@as(?usize, 1), placed_label.?.offset);
}

test "jump resolution" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    const end_label = try seq.newLabel();
    try seq.addJump(Opcode.JUMP_ABSOLUTE, end_label);
    try seq.addOpArg(Opcode.LOAD_CONST, 1);
    try seq.placeLabel(end_label);
    try seq.addOp(Opcode.RETURN_VALUE);

    try seq.resolveJumps();

    // Jump should point to instruction 2
    try std.testing.expectEqual(@as(u32, 2), seq.instructions.items[0].arg);
}

test "stack depth tracking" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 1); // +1
    try seq.addOpArg(Opcode.LOAD_CONST, 2); // +1
    try seq.addOp(Opcode.BINARY_ADD); // -1
    try seq.addOp(Opcode.RETURN_VALUE); // -1

    try std.testing.expectEqual(@as(i32, 2), seq.max_stack_depth);
    try std.testing.expectEqual(@as(i32, 0), seq.stack_depth);
}

test "bytecode generation" {
    const allocator = std.testing.allocator;
    var seq = InstructionSequence.init(allocator);
    defer seq.deinit();

    try seq.addOpArg(Opcode.LOAD_CONST, 42);
    try seq.addOp(Opcode.RETURN_VALUE);

    const bytecode = try seq.toBytecode(allocator);
    defer allocator.free(bytecode);

    try std.testing.expectEqual(@as(usize, 10), bytecode.len); // 2 instructions * 5 bytes
    try std.testing.expectEqual(Opcode.LOAD_CONST, bytecode[0]);
}

test "line number table" {
    const allocator = std.testing.allocator;
    var table = LineNumberTable.init(allocator);
    defer table.deinit();

    try table.addEntry(0, 1);
    try table.addEntry(3, 2);
    try table.addEntry(5, 3);

    try std.testing.expectEqual(@as(u32, 1), table.findLine(0));
    try std.testing.expectEqual(@as(u32, 1), table.findLine(2));
    try std.testing.expectEqual(@as(u32, 2), table.findLine(3));
    try std.testing.expectEqual(@as(u32, 3), table.findLine(10));
}

test "stack effects" {
    try std.testing.expectEqual(@as(i32, 1), getStackEffect(Opcode.LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), getStackEffect(Opcode.POP_TOP, 0));
    try std.testing.expectEqual(@as(i32, -1), getStackEffect(Opcode.BINARY_ADD, 0));
    try std.testing.expectEqual(@as(i32, 0), getStackEffect(Opcode.JUMP_ABSOLUTE, 0));
}

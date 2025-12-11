/// assemble - Bytecode Assembler
/// Mirrors cpython/Python/assemble.c
///
/// The assembler converts compiler-generated instructions into bytecode.
/// It handles jump target resolution, exception table generation, and
/// line number tables.

// Re-export all submodules
pub const instruction = @import("assemble/instruction.zig");
pub const basic_block = @import("assemble/basic_block.zig");
pub const types = @import("assemble/types.zig");
pub const utils = @import("assemble/utils.zig");
pub const assembler = @import("assemble/assembler.zig");
pub const pipeline = @import("assemble/pipeline.zig");

// Re-export commonly used types and constants
pub const Instruction = instruction.Instruction;
pub const BasicBlock = basic_block.BasicBlock;
pub const Assembler = assembler.Assembler;
pub const AssembledCode = types.AssembledCode;
pub const ExceptionEntry = types.ExceptionEntry;
pub const Constant = types.Constant;

// Re-export constants
pub const MAX_BYTECODE_OFFSET = instruction.MAX_BYTECODE_OFFSET;
pub const EXTENDED_ARG_THRESHOLD = instruction.EXTENDED_ARG_THRESHOLD;
pub const MAX_INSTRUCTION_SIZE = instruction.MAX_INSTRUCTION_SIZE;

// Re-export opcodes
pub const NOP = instruction.NOP;
pub const LOAD_CONST = instruction.LOAD_CONST;
pub const RETURN_VALUE = instruction.RETURN_VALUE;
pub const JUMP_FORWARD = instruction.JUMP_FORWARD;
pub const JUMP_ABSOLUTE = instruction.JUMP_ABSOLUTE;
pub const POP_JUMP_IF_TRUE = instruction.POP_JUMP_IF_TRUE;
pub const POP_JUMP_IF_FALSE = instruction.POP_JUMP_IF_FALSE;
pub const EXTENDED_ARG = instruction.EXTENDED_ARG;

// Re-export utility functions
pub const stackEffect = utils.stackEffect;
pub const hasArg = utils.hasArg;
pub const isJumpOpcode = utils.isJumpOpcode;
pub const init = utils.init;
pub const reset = utils.reset;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "basic block creation" {
    const allocator = std.testing.allocator;

    var asm = Assembler.init(allocator);
    defer asm.deinit();

    const block1 = try asm.newBlock();
    const block2 = try asm.newBlock();

    try std.testing.expectEqual(@as(u32, 0), block1.id);
    try std.testing.expectEqual(@as(u32, 1), block2.id);
}

test "instruction emission" {
    const allocator = std.testing.allocator;

    var asm = Assembler.init(allocator);
    defer asm.deinit();

    const block = try asm.newBlock();
    asm.setEntry(block);

    try asm.emit(LOAD_CONST, 0);
    try asm.emit(RETURN_VALUE, 0);

    try std.testing.expectEqual(@as(usize, 2), block.instructions.items.len);
}

test "constant deduplication" {
    const allocator = std.testing.allocator;

    var asm = Assembler.init(allocator);
    defer asm.deinit();

    const idx1 = try asm.addConstant(.{ .integer = 42 });
    const idx2 = try asm.addConstant(.{ .integer = 42 });
    const idx3 = try asm.addConstant(.{ .integer = 100 });

    try std.testing.expectEqual(idx1, idx2);
    try std.testing.expect(idx1 != idx3);
}

test "instruction size calculation" {
    const small = Instruction{ .opcode = LOAD_CONST, .arg = 10 };
    const medium = Instruction{ .opcode = LOAD_CONST, .arg = 1000 };
    const large = Instruction{ .opcode = LOAD_CONST, .arg = 100000 };

    try std.testing.expectEqual(@as(usize, 2), small.size());
    try std.testing.expectEqual(@as(usize, 4), medium.size());
    try std.testing.expectEqual(@as(usize, 6), large.size());
}

test "basic assembly" {
    const allocator = std.testing.allocator;

    var asm = Assembler.init(allocator);
    defer asm.deinit();

    const block = try asm.newBlock();
    asm.setEntry(block);

    _ = try asm.addConstant(.none);
    try asm.emit(LOAD_CONST, 0);
    try asm.emit(RETURN_VALUE, 0);

    const code = try asm.assemble();
    defer allocator.free(code.bytecode);
    defer allocator.free(code.linetable);
    defer allocator.free(code.exception_table);
    defer allocator.free(code.constants);
    defer allocator.free(code.names);

    try std.testing.expectEqual(@as(usize, 4), code.bytecode.len);
}

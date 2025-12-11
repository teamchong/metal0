/// Utility Functions for Bytecode Operations
/// Stack effect calculations, jump classification, and disassembly

const constants = @import("constants.zig");
const metadata = @import("metadata.zig");

// ============================================================================
// Stack Effect Calculations
// ============================================================================

/// Get stack effect for opcode
pub fn stackEffect(opcode: u8, arg: u32) i32 {
    const info = metadata.OPCODE_TABLE[opcode];
    var effect: i32 = info.stack_effect;

    // Adjust for variable stack effects
    switch (opcode) {
        constants.BUILD_TUPLE, constants.BUILD_LIST, constants.BUILD_SET => {
            // Pops arg items, pushes 1
            effect = 1 - @as(i32, @intCast(arg));
        },
        constants.BUILD_MAP => {
            // Pops 2*arg items, pushes 1
            effect = 1 - @as(i32, @intCast(2 * arg));
        },
        constants.BUILD_STRING => {
            // Pops arg items, pushes 1
            effect = 1 - @as(i32, @intCast(arg));
        },
        constants.CALL => {
            // Pops callable + arg positional + 1 if has kwargs
            effect = -@as(i32, @intCast(arg)) - 1;
        },
        constants.UNPACK_SEQUENCE => {
            // Pops 1, pushes arg items
            effect = @as(i32, @intCast(arg)) - 1;
        },
        constants.MAKE_FUNCTION => {
            // Complex - depends on flags
            effect = -@as(i32, @popCount(arg & 0x0F));
        },
        else => {},
    }

    return effect;
}

// ============================================================================
// Jump Classification
// ============================================================================

/// Check if opcode is unconditional jump
pub fn isUnconditionalJump(opcode: u8) bool {
    return opcode == constants.JUMP_FORWARD or
        opcode == constants.JUMP_BACKWARD or
        opcode == constants.JUMP_BACKWARD_NO_INTERRUPT;
}

/// Check if opcode is conditional jump
pub fn isConditionalJump(opcode: u8) bool {
    return opcode == constants.POP_JUMP_IF_FALSE or
        opcode == constants.POP_JUMP_IF_TRUE or
        opcode == constants.JUMP_IF_FALSE_OR_POP or
        opcode == constants.JUMP_IF_TRUE_OR_POP or
        opcode == constants.FOR_ITER;
}

/// Check if opcode terminates a basic block
pub fn isBlockTerminator(opcode: u8) bool {
    return opcode == constants.RETURN_VALUE or
        opcode == constants.RETURN_CONST or
        opcode == constants.RAISE_VARARGS or
        isUnconditionalJump(opcode);
}

// ============================================================================
// Disassembly
// ============================================================================

/// Disassemble single instruction
pub fn disassembleInstruction(bytecode: []const u8, offset: usize) struct { opcode: u8, arg: u32, next_offset: usize } {
    if (offset >= bytecode.len) {
        return .{ .opcode = constants.NOP, .arg = 0, .next_offset = bytecode.len };
    }

    var arg: u32 = 0;
    var pos = offset;

    // Handle EXTENDED_ARG
    while (pos < bytecode.len and bytecode[pos] == constants.EXTENDED_ARG) {
        arg = (arg | bytecode[pos + 1]) << 8;
        pos += 2;
    }

    if (pos + 1 < bytecode.len) {
        arg |= bytecode[pos + 1];
    }

    return .{
        .opcode = bytecode[pos],
        .arg = arg,
        .next_offset = pos + 2 + @as(usize, metadata.cacheEntries(bytecode[pos])) * 2,
    };
}

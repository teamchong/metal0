/// Utils - Assembler Utility Functions
/// Mirrors cpython/Python/assemble.c - helper functions

const instruction = @import("instruction.zig");

/// Calculate stack effect of an opcode
pub fn stackEffect(opcode: u8, arg: u32, jump: bool) i32 {
    _ = arg;
    _ = jump;
    return switch (opcode) {
        instruction.NOP => 0,
        instruction.LOAD_CONST => 1,
        instruction.RETURN_VALUE => -1,
        else => 0,
    };
}

/// Check if opcode has argument
pub fn hasArg(opcode: u8) bool {
    return opcode >= 90; // HAVE_ARGUMENT threshold
}

/// Check if opcode is a jump
pub fn isJumpOpcode(opcode: u8) bool {
    return opcode == instruction.JUMP_FORWARD or
        opcode == instruction.JUMP_ABSOLUTE or
        opcode == instruction.POP_JUMP_IF_TRUE or
        opcode == instruction.POP_JUMP_IF_FALSE;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the assembler module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

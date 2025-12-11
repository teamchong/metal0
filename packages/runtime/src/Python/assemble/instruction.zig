/// Instruction - Bytecode Instruction Types
/// Mirrors cpython/Python/assemble.c - instruction representation

const std = @import("std");

// Forward declaration for BasicBlock
const BasicBlock = @import("basic_block.zig").BasicBlock;

// ============================================================================
// Bytecode Constants
// ============================================================================

/// Maximum bytecode offset (24-bit)
pub const MAX_BYTECODE_OFFSET: u32 = 0xFFFFFF;

/// Extended arg threshold
pub const EXTENDED_ARG_THRESHOLD: u32 = 256;

/// Maximum instruction size (in bytes)
pub const MAX_INSTRUCTION_SIZE: usize = 10;

// ============================================================================
// Opcodes
// ============================================================================

pub const NOP: u8 = 9;
pub const LOAD_CONST: u8 = 100;
pub const RETURN_VALUE: u8 = 83;
pub const JUMP_FORWARD: u8 = 110;
pub const JUMP_ABSOLUTE: u8 = 113;
pub const POP_JUMP_IF_TRUE: u8 = 115;
pub const POP_JUMP_IF_FALSE: u8 = 114;
pub const EXTENDED_ARG: u8 = 144;

// ============================================================================
// Instruction Type
// ============================================================================

/// Raw instruction before assembly
pub const Instruction = struct {
    /// Opcode
    opcode: u8,
    /// Operand (may require EXTENDED_ARG)
    arg: u32 = 0,
    /// Source line number
    lineno: i32 = 0,
    /// Column offset
    col_offset: i32 = 0,
    /// End line number
    end_lineno: i32 = 0,
    /// End column offset
    end_col_offset: i32 = 0,
    /// Jump target (for branch instructions)
    target: ?*BasicBlock = null,
    /// Exception handler block
    except_handler: ?*BasicBlock = null,

    /// Check if instruction is a jump
    pub fn isJump(self: *const Instruction) bool {
        return self.target != null;
    }

    /// Check if instruction is unconditional jump
    pub fn isUnconditionalJump(self: *const Instruction) bool {
        return self.opcode == JUMP_ABSOLUTE or self.opcode == JUMP_FORWARD;
    }

    /// Get instruction size in bytes
    pub fn size(self: *const Instruction) usize {
        if (self.arg < EXTENDED_ARG_THRESHOLD) {
            return 2;
        } else if (self.arg < 0x10000) {
            return 4;
        } else if (self.arg < 0x1000000) {
            return 6;
        } else {
            return 8;
        }
    }
};

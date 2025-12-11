/// Core types for instruction sequences
/// Defines Instruction, Label, ExceptionHandler, and Opcode constants

const std = @import("std");

// ============================================================================
// Instruction Types
// ============================================================================

/// Bytecode instruction
pub const Instruction = struct {
    /// Opcode
    opcode: u8,
    /// Argument (or 0 if none)
    arg: u32 = 0,
    /// Line number in source
    lineno: u32 = 0,
    /// Column offset
    col_offset: u16 = 0,
    /// End column offset
    end_col_offset: u16 = 0,
    /// Jump target label (if branch)
    target: ?LabelId = null,
};

/// Label identifier
pub const LabelId = u32;

/// Special label values
pub const LABEL_NONE: LabelId = std.math.maxInt(LabelId);

/// Label entry
pub const Label = struct {
    /// Label ID
    id: LabelId,
    /// Byte offset (filled during resolution)
    offset: ?usize = null,
    /// Whether label has been placed
    placed: bool = false,
};

// ============================================================================
// Exception Handler
// ============================================================================

/// Exception handler entry
pub const ExceptionHandler = struct {
    /// Start offset (instruction index)
    start: usize,
    /// End offset
    end: usize,
    /// Handler offset
    handler: usize,
    /// Stack depth at handler
    depth: u16 = 0,
    /// Exception type (or null for bare except)
    type_name: ?[]const u8 = null,
};

// ============================================================================
// Opcodes (subset for reference)
// ============================================================================

pub const Opcode = struct {
    pub const LOAD_CONST: u8 = 1;
    pub const LOAD_NAME: u8 = 2;
    pub const LOAD_FAST: u8 = 3;
    pub const LOAD_GLOBAL: u8 = 4;
    pub const LOAD_ATTR: u8 = 5;

    pub const POP_TOP: u8 = 10;
    pub const STORE_NAME: u8 = 11;
    pub const STORE_FAST: u8 = 12;
    pub const STORE_GLOBAL: u8 = 13;
    pub const STORE_ATTR: u8 = 14;

    pub const BINARY_ADD: u8 = 20;
    pub const BINARY_SUBTRACT: u8 = 21;
    pub const BINARY_MULTIPLY: u8 = 22;
    pub const BINARY_DIVIDE: u8 = 23;
    pub const BINARY_MODULO: u8 = 24;
    pub const BINARY_POWER: u8 = 25;

    pub const UNARY_NEGATIVE: u8 = 30;
    pub const UNARY_NOT: u8 = 31;
    pub const UNARY_INVERT: u8 = 32;

    pub const COMPARE_OP: u8 = 40;

    pub const JUMP_ABSOLUTE: u8 = 50;
    pub const JUMP_IF_FALSE_OR_POP: u8 = 51;
    pub const JUMP_IF_TRUE_OR_POP: u8 = 52;
    pub const POP_JUMP_IF_FALSE: u8 = 53;
    pub const POP_JUMP_IF_TRUE: u8 = 54;

    pub const CALL_FUNCTION: u8 = 60;

    pub const RETURN_VALUE: u8 = 70;

    pub const BUILD_TUPLE: u8 = 80;
    pub const BUILD_LIST: u8 = 81;
    pub const BUILD_MAP: u8 = 82;

    pub const NOP: u8 = 0;
};

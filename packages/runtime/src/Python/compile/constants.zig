/// Bytecode constants: opcodes, instructions, and constant pool types
const std = @import("std");

/// Bytecode instruction opcodes
pub const OpCode = enum(u8) {
    // Stack operations
    LoadConst, // Push constant to stack
    Pop, // Pop from stack

    // Arithmetic
    Add, // Pop 2, push result
    Sub,
    Mult,
    Div,
    FloorDiv,
    Mod,
    Pow,

    // Unary operations
    Invert, // Bitwise NOT ~
    UAdd, // Unary + (type check only)
    USub, // Unary - (negate)

    // Comparisons
    Eq,
    NotEq,
    Lt,
    Gt,
    LtE,
    GtE,

    // Control
    Return, // Return top of stack
    Call, // Call builtin function
    BuildList, // Build list from N stack items
};

/// Bytecode instruction
pub const Instruction = struct {
    op: OpCode,
    arg: u32 = 0, // Argument (constant index, etc.)
};

/// Constant pool value
pub const Constant = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    bool: bool,
    bigint: []const u8, // BigInt stored as decimal string for serialization
    complex: f64, // Complex number (imaginary part only, e.g., 2j = complex(2.0))
};

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
    Invert, // Bitwise NOT ~ (0x53)
    UAdd, // Unary + (type check only) (0x51)
    USub, // Unary - (negate) (0x50)
    Not, // Boolean not (0x52)

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

    // Name lookup (for eval with scope)
    LoadName, // Load variable: tries locals -> globals -> builtins
    LoadGlobal, // Load from globals dict only
    LoadLocal, // Load from locals dict only
    StoreName, // Store to current scope (for exec())
    StoreGlobal, // Store to globals
    StoreLocal, // Store to locals
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
    none: void, // Python None
};

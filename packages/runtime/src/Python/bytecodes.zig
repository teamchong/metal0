/// bytecodes - Bytecode Definitions
/// Mirrors cpython/Python/bytecodes.c
///
/// This module defines all Python bytecode opcodes and their metadata.
/// Python 3.12+ uses a new bytecode format with 16-bit instruction words.

const std = @import("std");

// ============================================================================
// Opcode Categories
// ============================================================================

/// Opcode does not have an argument
pub const OPCODE_NO_ARG: u8 = 0;
/// Opcode has a regular argument
pub const OPCODE_HAS_ARG: u8 = 1;
/// Opcode is a jump instruction
pub const OPCODE_IS_JUMP: u8 = 2;
/// Opcode is a relative jump
pub const OPCODE_REL_JUMP: u8 = 4;
/// Opcode has a local variable argument
pub const OPCODE_HAS_LOCAL: u8 = 8;
/// Opcode has a free variable argument
pub const OPCODE_HAS_FREE: u8 = 16;
/// Opcode has a constant argument
pub const OPCODE_HAS_CONST: u8 = 32;
/// Opcode has a name argument
pub const OPCODE_HAS_NAME: u8 = 64;

// ============================================================================
// Bytecode Opcodes (Python 3.12+)
// ============================================================================

/// No operation
pub const NOP: u8 = 0;

/// Stack manipulation
pub const POP_TOP: u8 = 1;
pub const PUSH_NULL: u8 = 2;
pub const END_FOR: u8 = 4;
pub const END_SEND: u8 = 5;

/// Unary operations
pub const UNARY_NEGATIVE: u8 = 11;
pub const UNARY_NOT: u8 = 12;
pub const UNARY_INVERT: u8 = 15;

/// Binary operations (with inline cache)
pub const BINARY_OP: u8 = 22;
pub const BINARY_SUBSCR: u8 = 25;

/// Subscript operations
pub const STORE_SUBSCR: u8 = 60;
pub const DELETE_SUBSCR: u8 = 61;

/// Iterators
pub const GET_ITER: u8 = 68;
pub const GET_YIELD_FROM_ITER: u8 = 69;

/// Print statement (Python 2 compat)
pub const PRINT_EXPR: u8 = 70;

/// Load operations
pub const LOAD_BUILD_CLASS: u8 = 71;
pub const GET_AWAITABLE: u8 = 73;

/// Async/Await
pub const LOAD_ASSERTION_ERROR: u8 = 74;

/// Return
pub const RETURN_VALUE: u8 = 83;
pub const RETURN_CONST: u8 = 121;

/// Yield
pub const YIELD_VALUE: u8 = 86;
pub const YIELD_FROM: u8 = 72;

/// Setup
pub const SETUP_ANNOTATIONS: u8 = 85;

/// Async
pub const ASYNC_GEN_WRAP: u8 = 87;
pub const PREP_RERAISE_STAR: u8 = 88;
pub const POP_EXCEPT: u8 = 89;

/// Store/Delete
pub const STORE_NAME: u8 = 90;
pub const DELETE_NAME: u8 = 91;
pub const UNPACK_SEQUENCE: u8 = 92;
pub const FOR_ITER: u8 = 93;
pub const UNPACK_EX: u8 = 94;

/// Attribute access
pub const STORE_ATTR: u8 = 95;
pub const DELETE_ATTR: u8 = 96;
pub const STORE_GLOBAL: u8 = 97;
pub const DELETE_GLOBAL: u8 = 98;

/// Swap and Copy
pub const SWAP: u8 = 99;
pub const LOAD_CONST: u8 = 100;
pub const LOAD_NAME: u8 = 101;

/// Build operations
pub const BUILD_TUPLE: u8 = 102;
pub const BUILD_LIST: u8 = 103;
pub const BUILD_SET: u8 = 104;
pub const BUILD_MAP: u8 = 105;
pub const LOAD_ATTR: u8 = 106;
pub const COMPARE_OP: u8 = 107;
pub const IMPORT_NAME: u8 = 108;
pub const IMPORT_FROM: u8 = 109;

/// Jump operations
pub const JUMP_FORWARD: u8 = 110;
pub const JUMP_BACKWARD: u8 = 140;
pub const POP_JUMP_IF_FALSE: u8 = 114;
pub const POP_JUMP_IF_TRUE: u8 = 115;
pub const JUMP_IF_FALSE_OR_POP: u8 = 111;
pub const JUMP_IF_TRUE_OR_POP: u8 = 112;
pub const JUMP_BACKWARD_NO_INTERRUPT: u8 = 134;

/// Load globals/fast/deref
pub const LOAD_GLOBAL: u8 = 116;
pub const LOAD_FAST: u8 = 124;
pub const STORE_FAST: u8 = 125;
pub const DELETE_FAST: u8 = 126;
pub const LOAD_FAST_CHECK: u8 = 127;
pub const LOAD_FAST_AND_CLEAR: u8 = 128;
pub const LOAD_DEREF: u8 = 137;
pub const STORE_DEREF: u8 = 138;
pub const DELETE_DEREF: u8 = 139;
pub const LOAD_CLASSDEREF: u8 = 148;

/// Closures
pub const COPY_FREE_VARS: u8 = 149;
pub const MAKE_CELL: u8 = 135;

/// Exception handling
pub const RAISE_VARARGS: u8 = 130;

/// Call operations
pub const CALL: u8 = 171;
pub const CALL_FUNCTION_EX: u8 = 142;
pub const PUSH_EXC_INFO: u8 = 35;
pub const CHECK_EXC_MATCH: u8 = 36;
pub const CHECK_EG_MATCH: u8 = 37;

/// Keyword arguments
pub const KW_NAMES: u8 = 172;

/// Make function
pub const MAKE_FUNCTION: u8 = 132;

/// Build operations continued
pub const BUILD_SLICE: u8 = 133;
pub const BUILD_STRING: u8 = 157;

/// Load/Store super attr
pub const LOAD_SUPER_ATTR: u8 = 141;

/// Match operations (pattern matching)
pub const MATCH_CLASS: u8 = 152;
pub const MATCH_MAPPING: u8 = 153;
pub const MATCH_SEQUENCE: u8 = 154;
pub const MATCH_KEYS: u8 = 155;

/// Format
pub const FORMAT_VALUE: u8 = 155;

/// Extended arg
pub const EXTENDED_ARG: u8 = 144;

/// List/Set/Dict comprehensions
pub const LIST_APPEND: u8 = 145;
pub const SET_ADD: u8 = 146;
pub const MAP_ADD: u8 = 147;

/// Context managers
pub const BEFORE_ASYNC_WITH: u8 = 52;
pub const BEFORE_WITH: u8 = 53;

/// Annotations
pub const GET_LEN: u8 = 30;
pub const GET_AITER: u8 = 50;
pub const GET_ANEXT: u8 = 51;

/// Resume (generators)
pub const RESUME: u8 = 151;

/// Send (generators)
pub const SEND: u8 = 123;

/// Copy
pub const COPY: u8 = 120;

/// Binary op names
pub const BINARY_OP_ADD: u8 = 0;
pub const BINARY_OP_SUBTRACT: u8 = 10;
pub const BINARY_OP_MULTIPLY: u8 = 5;
pub const BINARY_OP_TRUE_DIVIDE: u8 = 11;
pub const BINARY_OP_FLOOR_DIVIDE: u8 = 2;
pub const BINARY_OP_MODULO: u8 = 6;
pub const BINARY_OP_POWER: u8 = 8;
pub const BINARY_OP_LSHIFT: u8 = 3;
pub const BINARY_OP_RSHIFT: u8 = 9;
pub const BINARY_OP_AND: u8 = 1;
pub const BINARY_OP_XOR: u8 = 12;
pub const BINARY_OP_OR: u8 = 7;
pub const BINARY_OP_MATMUL: u8 = 4;
pub const BINARY_OP_INPLACE_ADD: u8 = 13;
pub const BINARY_OP_INPLACE_SUBTRACT: u8 = 23;

/// Comparison operators
pub const COMPARE_LT: u8 = 0;
pub const COMPARE_LE: u8 = 1;
pub const COMPARE_EQ: u8 = 2;
pub const COMPARE_NE: u8 = 3;
pub const COMPARE_GT: u8 = 4;
pub const COMPARE_GE: u8 = 5;

// ============================================================================
// Opcode Metadata
// ============================================================================

/// Opcode information
pub const OpcodeInfo = struct {
    /// Opcode name
    name: []const u8,
    /// Stack effect
    stack_effect: i8,
    /// Opcode flags
    flags: u8,
    /// Number of cache entries (for specialized opcodes)
    cache_entries: u8 = 0,

    /// Check if opcode has argument
    pub fn hasArg(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_HAS_ARG) != 0;
    }

    /// Check if opcode is a jump
    pub fn isJump(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_IS_JUMP) != 0;
    }

    /// Check if opcode is a relative jump
    pub fn isRelativeJump(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_REL_JUMP) != 0;
    }

    /// Check if opcode has local variable argument
    pub fn hasLocal(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_HAS_LOCAL) != 0;
    }

    /// Check if opcode has free variable argument
    pub fn hasFree(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_HAS_FREE) != 0;
    }

    /// Check if opcode has constant argument
    pub fn hasConst(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_HAS_CONST) != 0;
    }

    /// Check if opcode has name argument
    pub fn hasName(self: *const OpcodeInfo) bool {
        return (self.flags & OPCODE_HAS_NAME) != 0;
    }
};

/// Opcode table - maps opcode to metadata
pub const OPCODE_TABLE: [256]OpcodeInfo = init_opcode_table();

fn init_opcode_table() [256]OpcodeInfo {
    var table: [256]OpcodeInfo = undefined;

    // Initialize all to unknown
    for (&table) |*entry| {
        entry.* = .{ .name = "UNKNOWN", .stack_effect = 0, .flags = 0 };
    }

    // Stack manipulation
    table[NOP] = .{ .name = "NOP", .stack_effect = 0, .flags = 0 };
    table[POP_TOP] = .{ .name = "POP_TOP", .stack_effect = -1, .flags = 0 };
    table[PUSH_NULL] = .{ .name = "PUSH_NULL", .stack_effect = 1, .flags = 0 };
    table[END_FOR] = .{ .name = "END_FOR", .stack_effect = -2, .flags = 0 };

    // Unary operations
    table[UNARY_NEGATIVE] = .{ .name = "UNARY_NEGATIVE", .stack_effect = 0, .flags = 0 };
    table[UNARY_NOT] = .{ .name = "UNARY_NOT", .stack_effect = 0, .flags = 0 };
    table[UNARY_INVERT] = .{ .name = "UNARY_INVERT", .stack_effect = 0, .flags = 0 };

    // Binary operations
    table[BINARY_OP] = .{ .name = "BINARY_OP", .stack_effect = -1, .flags = OPCODE_HAS_ARG, .cache_entries = 1 };
    table[BINARY_SUBSCR] = .{ .name = "BINARY_SUBSCR", .stack_effect = -1, .flags = 0, .cache_entries = 1 };
    table[STORE_SUBSCR] = .{ .name = "STORE_SUBSCR", .stack_effect = -3, .flags = 0, .cache_entries = 1 };
    table[DELETE_SUBSCR] = .{ .name = "DELETE_SUBSCR", .stack_effect = -2, .flags = 0 };

    // Load/Store operations
    table[LOAD_CONST] = .{ .name = "LOAD_CONST", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_CONST };
    table[LOAD_NAME] = .{ .name = "LOAD_NAME", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };
    table[STORE_NAME] = .{ .name = "STORE_NAME", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };
    table[DELETE_NAME] = .{ .name = "DELETE_NAME", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };

    table[LOAD_GLOBAL] = .{ .name = "LOAD_GLOBAL", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME, .cache_entries = 4 };
    table[STORE_GLOBAL] = .{ .name = "STORE_GLOBAL", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };
    table[DELETE_GLOBAL] = .{ .name = "DELETE_GLOBAL", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };

    table[LOAD_FAST] = .{ .name = "LOAD_FAST", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_LOCAL };
    table[LOAD_FAST_CHECK] = .{ .name = "LOAD_FAST_CHECK", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_LOCAL };
    table[LOAD_FAST_AND_CLEAR] = .{ .name = "LOAD_FAST_AND_CLEAR", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_LOCAL };
    table[STORE_FAST] = .{ .name = "STORE_FAST", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_LOCAL };
    table[DELETE_FAST] = .{ .name = "DELETE_FAST", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_LOCAL };

    table[LOAD_DEREF] = .{ .name = "LOAD_DEREF", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_FREE };
    table[STORE_DEREF] = .{ .name = "STORE_DEREF", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_FREE };
    table[DELETE_DEREF] = .{ .name = "DELETE_DEREF", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_FREE };

    // Attribute access
    table[LOAD_ATTR] = .{ .name = "LOAD_ATTR", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME, .cache_entries = 9 };
    table[STORE_ATTR] = .{ .name = "STORE_ATTR", .stack_effect = -2, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME, .cache_entries = 4 };
    table[DELETE_ATTR] = .{ .name = "DELETE_ATTR", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };

    // Build operations
    table[BUILD_TUPLE] = .{ .name = "BUILD_TUPLE", .stack_effect = 0, .flags = OPCODE_HAS_ARG }; // stack effect varies
    table[BUILD_LIST] = .{ .name = "BUILD_LIST", .stack_effect = 0, .flags = OPCODE_HAS_ARG };
    table[BUILD_SET] = .{ .name = "BUILD_SET", .stack_effect = 0, .flags = OPCODE_HAS_ARG };
    table[BUILD_MAP] = .{ .name = "BUILD_MAP", .stack_effect = 0, .flags = OPCODE_HAS_ARG };
    table[BUILD_STRING] = .{ .name = "BUILD_STRING", .stack_effect = 0, .flags = OPCODE_HAS_ARG };
    table[BUILD_SLICE] = .{ .name = "BUILD_SLICE", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Jump operations
    table[JUMP_FORWARD] = .{ .name = "JUMP_FORWARD", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP | OPCODE_REL_JUMP };
    table[JUMP_BACKWARD] = .{ .name = "JUMP_BACKWARD", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP | OPCODE_REL_JUMP };
    table[JUMP_BACKWARD_NO_INTERRUPT] = .{ .name = "JUMP_BACKWARD_NO_INTERRUPT", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP | OPCODE_REL_JUMP };
    table[POP_JUMP_IF_FALSE] = .{ .name = "POP_JUMP_IF_FALSE", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP };
    table[POP_JUMP_IF_TRUE] = .{ .name = "POP_JUMP_IF_TRUE", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP };
    table[JUMP_IF_FALSE_OR_POP] = .{ .name = "JUMP_IF_FALSE_OR_POP", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP };
    table[JUMP_IF_TRUE_OR_POP] = .{ .name = "JUMP_IF_TRUE_OR_POP", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP };

    // Comparison
    table[COMPARE_OP] = .{ .name = "COMPARE_OP", .stack_effect = -1, .flags = OPCODE_HAS_ARG, .cache_entries = 1 };

    // Return/Yield
    table[RETURN_VALUE] = .{ .name = "RETURN_VALUE", .stack_effect = -1, .flags = 0 };
    table[RETURN_CONST] = .{ .name = "RETURN_CONST", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_CONST };
    table[YIELD_VALUE] = .{ .name = "YIELD_VALUE", .stack_effect = 0, .flags = 0 };

    // Iterator
    table[GET_ITER] = .{ .name = "GET_ITER", .stack_effect = 0, .flags = 0 };
    table[FOR_ITER] = .{ .name = "FOR_ITER", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_IS_JUMP, .cache_entries = 1 };

    // Call
    table[CALL] = .{ .name = "CALL", .stack_effect = 0, .flags = OPCODE_HAS_ARG, .cache_entries = 3 };
    table[CALL_FUNCTION_EX] = .{ .name = "CALL_FUNCTION_EX", .stack_effect = -1, .flags = OPCODE_HAS_ARG };
    table[KW_NAMES] = .{ .name = "KW_NAMES", .stack_effect = 0, .flags = OPCODE_HAS_ARG | OPCODE_HAS_CONST };

    // Functions
    table[MAKE_FUNCTION] = .{ .name = "MAKE_FUNCTION", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Imports
    table[IMPORT_NAME] = .{ .name = "IMPORT_NAME", .stack_effect = -1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };
    table[IMPORT_FROM] = .{ .name = "IMPORT_FROM", .stack_effect = 1, .flags = OPCODE_HAS_ARG | OPCODE_HAS_NAME };

    // Unpack
    table[UNPACK_SEQUENCE] = .{ .name = "UNPACK_SEQUENCE", .stack_effect = 0, .flags = OPCODE_HAS_ARG, .cache_entries = 1 };
    table[UNPACK_EX] = .{ .name = "UNPACK_EX", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Exception handling
    table[RAISE_VARARGS] = .{ .name = "RAISE_VARARGS", .stack_effect = 0, .flags = OPCODE_HAS_ARG };
    table[POP_EXCEPT] = .{ .name = "POP_EXCEPT", .stack_effect = -1, .flags = 0 };
    table[PUSH_EXC_INFO] = .{ .name = "PUSH_EXC_INFO", .stack_effect = 1, .flags = 0 };
    table[CHECK_EXC_MATCH] = .{ .name = "CHECK_EXC_MATCH", .stack_effect = 0, .flags = 0 };

    // Extended arg
    table[EXTENDED_ARG] = .{ .name = "EXTENDED_ARG", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Comprehensions
    table[LIST_APPEND] = .{ .name = "LIST_APPEND", .stack_effect = -1, .flags = OPCODE_HAS_ARG };
    table[SET_ADD] = .{ .name = "SET_ADD", .stack_effect = -1, .flags = OPCODE_HAS_ARG };
    table[MAP_ADD] = .{ .name = "MAP_ADD", .stack_effect = -2, .flags = OPCODE_HAS_ARG };

    // Copy/Swap
    table[COPY] = .{ .name = "COPY", .stack_effect = 1, .flags = OPCODE_HAS_ARG };
    table[SWAP] = .{ .name = "SWAP", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Resume
    table[RESUME] = .{ .name = "RESUME", .stack_effect = 0, .flags = OPCODE_HAS_ARG };

    // Pattern matching
    table[MATCH_MAPPING] = .{ .name = "MATCH_MAPPING", .stack_effect = 1, .flags = 0 };
    table[MATCH_SEQUENCE] = .{ .name = "MATCH_SEQUENCE", .stack_effect = 1, .flags = 0 };
    table[MATCH_KEYS] = .{ .name = "MATCH_KEYS", .stack_effect = 1, .flags = 0 };
    table[MATCH_CLASS] = .{ .name = "MATCH_CLASS", .stack_effect = -1, .flags = OPCODE_HAS_ARG };

    return table;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Get opcode name
pub fn opcodeName(opcode: u8) []const u8 {
    return OPCODE_TABLE[opcode].name;
}

/// Get stack effect for opcode
pub fn stackEffect(opcode: u8, arg: u32) i32 {
    const info = OPCODE_TABLE[opcode];
    var effect: i32 = info.stack_effect;

    // Adjust for variable stack effects
    switch (opcode) {
        BUILD_TUPLE, BUILD_LIST, BUILD_SET => {
            // Pops arg items, pushes 1
            effect = 1 - @as(i32, @intCast(arg));
        },
        BUILD_MAP => {
            // Pops 2*arg items, pushes 1
            effect = 1 - @as(i32, @intCast(2 * arg));
        },
        BUILD_STRING => {
            // Pops arg items, pushes 1
            effect = 1 - @as(i32, @intCast(arg));
        },
        CALL => {
            // Pops callable + arg positional + 1 if has kwargs
            effect = -@as(i32, @intCast(arg)) - 1;
        },
        UNPACK_SEQUENCE => {
            // Pops 1, pushes arg items
            effect = @as(i32, @intCast(arg)) - 1;
        },
        MAKE_FUNCTION => {
            // Complex - depends on flags
            effect = -@as(i32, @popCount(arg & 0x0F));
        },
        else => {},
    }

    return effect;
}

/// Check if opcode is unconditional jump
pub fn isUnconditionalJump(opcode: u8) bool {
    return opcode == JUMP_FORWARD or
        opcode == JUMP_BACKWARD or
        opcode == JUMP_BACKWARD_NO_INTERRUPT;
}

/// Check if opcode is conditional jump
pub fn isConditionalJump(opcode: u8) bool {
    return opcode == POP_JUMP_IF_FALSE or
        opcode == POP_JUMP_IF_TRUE or
        opcode == JUMP_IF_FALSE_OR_POP or
        opcode == JUMP_IF_TRUE_OR_POP or
        opcode == FOR_ITER;
}

/// Check if opcode terminates a basic block
pub fn isBlockTerminator(opcode: u8) bool {
    return opcode == RETURN_VALUE or
        opcode == RETURN_CONST or
        opcode == RAISE_VARARGS or
        isUnconditionalJump(opcode);
}

/// Get number of inline cache entries for opcode
pub fn cacheEntries(opcode: u8) u8 {
    return OPCODE_TABLE[opcode].cache_entries;
}

/// Disassemble single instruction
pub fn disassembleInstruction(bytecode: []const u8, offset: usize) struct { opcode: u8, arg: u32, next_offset: usize } {
    if (offset >= bytecode.len) {
        return .{ .opcode = NOP, .arg = 0, .next_offset = bytecode.len };
    }

    const opcode = bytecode[offset];
    var arg: u32 = 0;
    var pos = offset;

    // Handle EXTENDED_ARG
    while (pos < bytecode.len and bytecode[pos] == EXTENDED_ARG) {
        arg = (arg | bytecode[pos + 1]) << 8;
        pos += 2;
    }

    if (pos + 1 < bytecode.len) {
        arg |= bytecode[pos + 1];
    }

    return .{
        .opcode = bytecode[pos],
        .arg = arg,
        .next_offset = pos + 2 + @as(usize, cacheEntries(bytecode[pos])) * 2,
    };
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the bytecodes module
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

test "opcode names" {
    try std.testing.expectEqualStrings("NOP", opcodeName(NOP));
    try std.testing.expectEqualStrings("LOAD_CONST", opcodeName(LOAD_CONST));
    try std.testing.expectEqualStrings("RETURN_VALUE", opcodeName(RETURN_VALUE));
}

test "opcode flags" {
    const load_const = OPCODE_TABLE[LOAD_CONST];
    try std.testing.expect(load_const.hasArg());
    try std.testing.expect(load_const.hasConst());
    try std.testing.expect(!load_const.isJump());

    const jump_forward = OPCODE_TABLE[JUMP_FORWARD];
    try std.testing.expect(jump_forward.isJump());
    try std.testing.expect(jump_forward.isRelativeJump());
}

test "stack effects" {
    try std.testing.expectEqual(@as(i32, 1), stackEffect(LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(RETURN_VALUE, 0));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(POP_TOP, 0));

    // Variable stack effects
    try std.testing.expectEqual(@as(i32, -2), stackEffect(BUILD_TUPLE, 3)); // 1 - 3
    try std.testing.expectEqual(@as(i32, -5), stackEffect(BUILD_MAP, 3)); // 1 - 6
}

test "jump classification" {
    try std.testing.expect(isUnconditionalJump(JUMP_FORWARD));
    try std.testing.expect(isUnconditionalJump(JUMP_BACKWARD));
    try std.testing.expect(!isUnconditionalJump(POP_JUMP_IF_FALSE));

    try std.testing.expect(isConditionalJump(POP_JUMP_IF_FALSE));
    try std.testing.expect(isConditionalJump(FOR_ITER));
    try std.testing.expect(!isConditionalJump(JUMP_FORWARD));
}

test "block terminators" {
    try std.testing.expect(isBlockTerminator(RETURN_VALUE));
    try std.testing.expect(isBlockTerminator(RETURN_CONST));
    try std.testing.expect(isBlockTerminator(RAISE_VARARGS));
    try std.testing.expect(isBlockTerminator(JUMP_FORWARD));
    try std.testing.expect(!isBlockTerminator(LOAD_CONST));
}

test "cache entries" {
    try std.testing.expectEqual(@as(u8, 0), cacheEntries(NOP));
    try std.testing.expectEqual(@as(u8, 1), cacheEntries(BINARY_OP));
    try std.testing.expectEqual(@as(u8, 4), cacheEntries(LOAD_GLOBAL));
    try std.testing.expectEqual(@as(u8, 9), cacheEntries(LOAD_ATTR));
}

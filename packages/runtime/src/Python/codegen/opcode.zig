/// opcode - Bytecode Opcodes
/// Mirrors cpython/Python/codegen.c opcode definitions
///
/// Defines the bytecode instruction set and stack effects.

const std = @import("std");

// ============================================================================
// Opcodes
// ============================================================================

/// Opcodes used by code generator
pub const Opcode = enum(u8) {
    NOP = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,

    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    BINARY_OP = 22,
    BINARY_SUBSCR = 25,

    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    GET_ITER = 68,

    RETURN_VALUE = 83,

    STORE_NAME = 90,
    DELETE_NAME = 91,
    UNPACK_SEQUENCE = 92,
    FOR_ITER = 93,

    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,

    LOAD_CONST = 100,
    LOAD_NAME = 101,
    BUILD_TUPLE = 102,
    BUILD_LIST = 103,
    BUILD_SET = 104,
    BUILD_MAP = 105,
    LOAD_ATTR = 106,
    COMPARE_OP = 107,
    IMPORT_NAME = 108,
    IMPORT_FROM = 109,

    JUMP_FORWARD = 110,
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,

    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,

    RAISE_VARARGS = 130,
    MAKE_FUNCTION = 132,
    BUILD_SLICE = 133,

    LOAD_DEREF = 137,
    STORE_DEREF = 138,
    DELETE_DEREF = 139,

    CALL = 171,
};

// ============================================================================
// Stack Effects
// ============================================================================

/// Get stack effect for opcode
pub fn opcodeStackEffect(opcode: Opcode, arg: u32) i32 {
    return switch (opcode) {
        .NOP => 0,
        .POP_TOP => -1,
        .PUSH_NULL => 1,
        .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
        .BINARY_OP, .BINARY_SUBSCR => -1,
        .STORE_SUBSCR => -3,
        .DELETE_SUBSCR => -2,
        .GET_ITER => 0,
        .RETURN_VALUE => -1,
        .STORE_NAME, .STORE_GLOBAL, .STORE_FAST, .STORE_DEREF => -1,
        .DELETE_NAME, .DELETE_GLOBAL, .DELETE_FAST, .DELETE_DEREF => 0,
        .STORE_ATTR => -2,
        .DELETE_ATTR => -1,
        .LOAD_CONST, .LOAD_NAME, .LOAD_GLOBAL, .LOAD_FAST, .LOAD_DEREF => 1,
        .LOAD_ATTR => 0,
        .COMPARE_OP => -1,
        .IMPORT_NAME => -1,
        .IMPORT_FROM => 1,
        .JUMP_FORWARD => 0,
        .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => -1,
        .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => blk: {
            break :blk 1 - @as(i32, @intCast(arg));
        },
        .BUILD_MAP => 1 - @as(i32, @intCast(2 * arg)),
        .UNPACK_SEQUENCE => @as(i32, @intCast(arg)) - 1,
        .FOR_ITER => 1,
        .RAISE_VARARGS => -@as(i32, @intCast(arg)),
        .MAKE_FUNCTION => -@as(i32, @popCount(arg & 0x0F)),
        .BUILD_SLICE => -@as(i32, @intCast(arg)) + 1,
        .CALL => -@as(i32, @intCast(arg)) - 1,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "opcode stack effects" {
    try std.testing.expectEqual(@as(i32, 1), opcodeStackEffect(.LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), opcodeStackEffect(.POP_TOP, 0));
    try std.testing.expectEqual(@as(i32, -1), opcodeStackEffect(.BINARY_OP, 0));
    try std.testing.expectEqual(@as(i32, -2), opcodeStackEffect(.BUILD_TUPLE, 3)); // 1 - 3
    try std.testing.expectEqual(@as(i32, -5), opcodeStackEffect(.BUILD_MAP, 3)); // 1 - 6
}

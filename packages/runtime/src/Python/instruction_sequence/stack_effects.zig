/// Stack effect calculations for opcodes
/// Used for tracking stack depth during bytecode generation

const types = @import("types.zig");
const Opcode = types.Opcode;

/// Get stack effect of opcode
pub fn getStackEffect(opcode: u8, arg: u32) i32 {
    // Common opcodes and their stack effects
    return switch (opcode) {
        // Push operations
        1 => 1, // LOAD_CONST
        2 => 1, // LOAD_NAME
        3 => 1, // LOAD_FAST
        4 => 1, // LOAD_GLOBAL
        5 => 1, // LOAD_ATTR (+1, but pops obj)

        // Pop operations
        10 => -1, // POP_TOP
        11 => -1, // STORE_NAME
        12 => -1, // STORE_FAST
        13 => -1, // STORE_GLOBAL
        14 => -2, // STORE_ATTR

        // Binary operations (pop 2, push 1)
        20 => -1, // BINARY_ADD
        21 => -1, // BINARY_SUBTRACT
        22 => -1, // BINARY_MULTIPLY
        23 => -1, // BINARY_DIVIDE
        24 => -1, // BINARY_MODULO
        25 => -1, // BINARY_POWER

        // Unary operations (pop 1, push 1)
        30 => 0, // UNARY_NEGATIVE
        31 => 0, // UNARY_NOT
        32 => 0, // UNARY_INVERT

        // Comparison (pop 2, push 1)
        40 => -1, // COMPARE_OP

        // Jumps (no stack effect for unconditional)
        50 => 0, // JUMP_ABSOLUTE
        51 => -1, // JUMP_IF_FALSE_OR_POP
        52 => -1, // JUMP_IF_TRUE_OR_POP
        53 => -1, // POP_JUMP_IF_FALSE
        54 => -1, // POP_JUMP_IF_TRUE

        // Function calls
        60 => -@as(i32, @intCast(arg)), // CALL_FUNCTION (pops func + args, pushes result)

        // Return
        70 => -1, // RETURN_VALUE

        // Build operations
        80 => 1 - @as(i32, @intCast(arg)), // BUILD_TUPLE
        81 => 1 - @as(i32, @intCast(arg)), // BUILD_LIST
        82 => 1 - @as(i32, @intCast(arg)) * 2, // BUILD_MAP

        // Default: no effect
        else => 0,
    };
}

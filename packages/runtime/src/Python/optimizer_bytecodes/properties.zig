/// properties - Micro-Op Properties
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Provides properties for micro-operations (stack effects, guards, jumps, etc).

const std = @import("std");
const bytecode_defs = @import("bytecode_defs.zig");

pub const MicroOp = bytecode_defs.MicroOp;

// ============================================================================
// Micro-op Properties
// ============================================================================

/// Micro-op properties
pub const MicroOpProps = struct {
    /// Stack effect
    stack_effect: i8,
    /// Has argument
    has_arg: bool,
    /// Is guard
    is_guard: bool,
    /// Is jump
    is_jump: bool,
    /// Can deoptimize
    can_deopt: bool,
};

/// Get properties for a micro-op
pub fn getMicroOpProps(op: MicroOp) MicroOpProps {
    return switch (op) {
        ._NOP => .{ .stack_effect = 0, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._LOAD_FAST, ._LOAD_FAST_BORROW => .{ .stack_effect = 1, .has_arg = true, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._STORE_FAST => .{ .stack_effect = -1, .has_arg = true, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._LOAD_CONST => .{ .stack_effect = 1, .has_arg = true, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._POP_TOP => .{ .stack_effect = -1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._PUSH_NULL => .{ .stack_effect = 1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = false },

        ._BINARY_OP, ._BINARY_OP_ADD, ._BINARY_OP_SUB, ._BINARY_OP_MUL => .{ .stack_effect = -1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = true },
        ._BINARY_OP_ADD_INT, ._BINARY_OP_SUB_INT, ._BINARY_OP_MUL_INT => .{ .stack_effect = -1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = true },
        ._BINARY_OP_ADD_FLOAT, ._BINARY_OP_SUB_FLOAT, ._BINARY_OP_MUL_FLOAT => .{ .stack_effect = -1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = false },

        ._COMPARE_OP, ._COMPARE_OP_INT, ._COMPARE_OP_FLOAT, ._COMPARE_OP_STR => .{ .stack_effect = -1, .has_arg = true, .is_guard = false, .is_jump = false, .can_deopt = false },

        ._JUMP => .{ .stack_effect = 0, .has_arg = true, .is_guard = false, .is_jump = true, .can_deopt = false },
        ._POP_JUMP_IF_TRUE, ._POP_JUMP_IF_FALSE => .{ .stack_effect = -1, .has_arg = true, .is_guard = false, .is_jump = true, .can_deopt = false },
        ._FOR_ITER, ._FOR_ITER_LIST, ._FOR_ITER_TUPLE, ._FOR_ITER_RANGE => .{ .stack_effect = 1, .has_arg = true, .is_guard = false, .is_jump = true, .can_deopt = false },

        ._GUARD_TYPE_INT, ._GUARD_TYPE_FLOAT, ._GUARD_TYPE_STR => .{ .stack_effect = 0, .has_arg = false, .is_guard = true, .is_jump = false, .can_deopt = true },
        ._GUARD_TYPE_LIST, ._GUARD_TYPE_TUPLE, ._GUARD_TYPE_DICT => .{ .stack_effect = 0, .has_arg = false, .is_guard = true, .is_jump = false, .can_deopt = true },
        ._GUARD_NOT_NONE => .{ .stack_effect = 0, .has_arg = false, .is_guard = true, .is_jump = false, .can_deopt = true },

        ._RETURN_VALUE => .{ .stack_effect = -1, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = false },
        ._DEOPT => .{ .stack_effect = 0, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = true },
        ._EXIT_TRACE => .{ .stack_effect = 0, .has_arg = false, .is_guard = false, .is_jump = true, .can_deopt = false },

        else => .{ .stack_effect = 0, .has_arg = false, .is_guard = false, .is_jump = false, .can_deopt = true },
    };
}

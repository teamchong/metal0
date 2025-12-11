/// translation - Bytecode Translation and Specialization
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Handles translation from bytecode to micro-ops and type-based specialization.

const std = @import("std");
const bytecode_defs = @import("bytecode_defs.zig");

pub const Bytecode = bytecode_defs.Bytecode;
pub const MicroOp = bytecode_defs.MicroOp;
pub const TypeId = bytecode_defs.TypeId;

// ============================================================================
// Translation Types
// ============================================================================

/// Translation entry from bytecode to micro-ops
pub const Translation = struct {
    /// Source bytecode
    bytecode: Bytecode,
    /// Micro-ops for this bytecode
    micro_ops: []const MicroOpEntry,
    /// Specialization possibilities
    specializations: []const Specialization,
};

/// Single micro-op entry
pub const MicroOpEntry = struct {
    op: MicroOp,
    arg_source: ArgSource = .none,
};

/// Argument source for micro-op
pub const ArgSource = enum {
    none,
    bytecode_arg,
    cache_0,
    cache_1,
    inline_value,
};

/// Specialization rule
pub const Specialization = struct {
    /// Condition for specialization
    condition: SpecCondition,
    /// Specialized micro-op
    specialized_op: MicroOp,
    /// Guard to insert
    guard: ?MicroOp = null,
};

/// Specialization condition
pub const SpecCondition = enum {
    operand_is_int,
    operand_is_float,
    operand_is_str,
    operand_is_list,
    operand_is_tuple,
    operand_is_dict,
    operands_same_type,
    attr_is_instance,
    attr_is_module,
    call_is_builtin,
};

// ============================================================================
// Bytecode Translation
// ============================================================================

/// Get micro-ops for a bytecode
pub fn translateBytecode(bytecode: Bytecode) []const MicroOpEntry {
    return switch (bytecode) {
        .NOP => &[_]MicroOpEntry{.{ .op = ._NOP }},
        .POP_TOP => &[_]MicroOpEntry{.{ .op = ._POP_TOP }},
        .PUSH_NULL => &[_]MicroOpEntry{.{ .op = ._PUSH_NULL }},

        .LOAD_FAST => &[_]MicroOpEntry{.{ .op = ._LOAD_FAST, .arg_source = .bytecode_arg }},
        .STORE_FAST => &[_]MicroOpEntry{.{ .op = ._STORE_FAST, .arg_source = .bytecode_arg }},
        .LOAD_CONST => &[_]MicroOpEntry{.{ .op = ._LOAD_CONST, .arg_source = .bytecode_arg }},

        .BINARY_OP => &[_]MicroOpEntry{.{ .op = ._BINARY_OP, .arg_source = .bytecode_arg }},
        .BINARY_SUBSCR => &[_]MicroOpEntry{.{ .op = ._BINARY_SUBSCR }},
        .STORE_SUBSCR => &[_]MicroOpEntry{.{ .op = ._STORE_SUBSCR }},

        .LOAD_ATTR => &[_]MicroOpEntry{
            .{ .op = ._LOAD_ATTR, .arg_source = .bytecode_arg },
        },
        .STORE_ATTR => &[_]MicroOpEntry{
            .{ .op = ._STORE_ATTR, .arg_source = .bytecode_arg },
        },

        .LOAD_GLOBAL => &[_]MicroOpEntry{
            .{ .op = ._GUARD_GLOBALS_VERSION, .arg_source = .cache_0 },
            .{ .op = ._LOAD_GLOBAL, .arg_source = .bytecode_arg },
        },

        .COMPARE_OP => &[_]MicroOpEntry{.{ .op = ._COMPARE_OP, .arg_source = .bytecode_arg }},

        .JUMP_FORWARD => &[_]MicroOpEntry{.{ .op = ._JUMP, .arg_source = .bytecode_arg }},
        .POP_JUMP_IF_FALSE => &[_]MicroOpEntry{.{ .op = ._POP_JUMP_IF_FALSE, .arg_source = .bytecode_arg }},
        .POP_JUMP_IF_TRUE => &[_]MicroOpEntry{.{ .op = ._POP_JUMP_IF_TRUE, .arg_source = .bytecode_arg }},
        .FOR_ITER => &[_]MicroOpEntry{.{ .op = ._FOR_ITER, .arg_source = .bytecode_arg }},

        .CALL => &[_]MicroOpEntry{.{ .op = ._CALL, .arg_source = .bytecode_arg }},
        .RETURN_VALUE => &[_]MicroOpEntry{.{ .op = ._RETURN_VALUE }},
        .RETURN_CONST => &[_]MicroOpEntry{
            .{ .op = ._LOAD_CONST, .arg_source = .bytecode_arg },
            .{ .op = ._RETURN_VALUE },
        },

        .BUILD_LIST => &[_]MicroOpEntry{.{ .op = ._BUILD_LIST, .arg_source = .bytecode_arg }},
        .BUILD_TUPLE => &[_]MicroOpEntry{.{ .op = ._BUILD_TUPLE, .arg_source = .bytecode_arg }},
        .BUILD_SET => &[_]MicroOpEntry{.{ .op = ._BUILD_SET, .arg_source = .bytecode_arg }},
        .BUILD_MAP => &[_]MicroOpEntry{.{ .op = ._BUILD_MAP, .arg_source = .bytecode_arg }},

        .UNARY_NEGATIVE => &[_]MicroOpEntry{.{ .op = ._UNARY_NEGATIVE }},
        .UNARY_NOT => &[_]MicroOpEntry{.{ .op = ._UNARY_NOT }},
        .UNARY_INVERT => &[_]MicroOpEntry{.{ .op = ._UNARY_INVERT }},

        .GET_ITER => &[_]MicroOpEntry{.{ .op = ._NOP }}, // Handled specially

        else => &[_]MicroOpEntry{.{ .op = ._DEOPT }},
    };
}

// ============================================================================
// Specialization
// ============================================================================

/// Get specialization for a micro-op based on type
pub fn specialize(op: MicroOp, operand_type: TypeId) MicroOp {
    return switch (op) {
        ._BINARY_OP_ADD => switch (operand_type) {
            .int_type => ._BINARY_OP_ADD_INT,
            .float_type => ._BINARY_OP_ADD_FLOAT,
            .str_type => ._BINARY_OP_ADD_STR,
            else => op,
        },
        ._BINARY_OP_SUB => switch (operand_type) {
            .int_type => ._BINARY_OP_SUB_INT,
            .float_type => ._BINARY_OP_SUB_FLOAT,
            else => op,
        },
        ._BINARY_OP_MUL => switch (operand_type) {
            .int_type => ._BINARY_OP_MUL_INT,
            .float_type => ._BINARY_OP_MUL_FLOAT,
            else => op,
        },
        ._COMPARE_OP => switch (operand_type) {
            .int_type => ._COMPARE_OP_INT,
            .float_type => ._COMPARE_OP_FLOAT,
            .str_type => ._COMPARE_OP_STR,
            else => op,
        },
        ._BINARY_SUBSCR => switch (operand_type) {
            .list_type => ._BINARY_SUBSCR_LIST,
            .tuple_type => ._BINARY_SUBSCR_TUPLE,
            .dict_type => ._BINARY_SUBSCR_DICT,
            .str_type => ._BINARY_SUBSCR_STR,
            else => op,
        },
        ._FOR_ITER => switch (operand_type) {
            .list_type => ._FOR_ITER_LIST,
            .tuple_type => ._FOR_ITER_TUPLE,
            else => op,
        },
        ._UNARY_NEGATIVE => switch (operand_type) {
            .int_type => ._UNARY_NEGATIVE_INT,
            .float_type => ._UNARY_NEGATIVE_FLOAT,
            else => op,
        },
        else => op,
    };
}

/// Get guard for a type
pub fn guardForType(type_id: TypeId) ?MicroOp {
    return switch (type_id) {
        .int_type => ._GUARD_TYPE_INT,
        .float_type => ._GUARD_TYPE_FLOAT,
        .str_type => ._GUARD_TYPE_STR,
        .list_type => ._GUARD_TYPE_LIST,
        .tuple_type => ._GUARD_TYPE_TUPLE,
        .dict_type => ._GUARD_TYPE_DICT,
        else => null,
    };
}

/// optimizer_bytecodes - Optimizer Bytecodes
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Defines optimized bytecode variants and micro-op translations
/// for the trace-based optimizer.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Optimized Bytecodes
// ============================================================================

/// Standard Python bytecodes
pub const Bytecode = enum(u16) {
    // Stack manipulation
    NOP = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,
    END_FOR = 4,
    END_SEND = 5,

    // Unary operations
    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    // Binary operations
    BINARY_OP = 22,
    BINARY_SUBSCR = 25,

    // Store/Delete subscript
    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    // Iterators
    GET_ITER = 68,
    GET_YIELD_FROM_ITER = 69,

    // Load operations
    LOAD_BUILD_CLASS = 71,

    // Return/Yield
    RETURN_VALUE = 83,
    RETURN_CONST = 121,
    YIELD_VALUE = 86,

    // Store/Delete
    STORE_NAME = 90,
    DELETE_NAME = 91,
    UNPACK_SEQUENCE = 92,
    FOR_ITER = 93,
    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,

    // Load
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

    // Jumps
    JUMP_FORWARD = 110,
    JUMP_IF_FALSE_OR_POP = 111,
    JUMP_IF_TRUE_OR_POP = 112,
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,

    // Fast locals
    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,

    // Call
    CALL = 171,

    // Extended arg
    EXTENDED_ARG = 144,
};

/// Micro-operation opcodes for optimized traces
pub const MicroOp = enum(u16) {
    // Core stack ops
    _NOP = 0,
    _LOAD_FAST = 1,
    _LOAD_FAST_BORROW = 2,
    _STORE_FAST = 3,
    _LOAD_CONST = 4,
    _POP_TOP = 5,
    _PUSH_NULL = 6,
    _COPY = 7,
    _SWAP = 8,

    // Binary operations - generic
    _BINARY_OP = 10,
    _BINARY_OP_ADD = 11,
    _BINARY_OP_SUB = 12,
    _BINARY_OP_MUL = 13,
    _BINARY_OP_DIV = 14,
    _BINARY_OP_MOD = 15,

    // Binary operations - specialized int
    _BINARY_OP_ADD_INT = 20,
    _BINARY_OP_SUB_INT = 21,
    _BINARY_OP_MUL_INT = 22,
    _BINARY_OP_ADD_INT_FAST = 23,
    _BINARY_OP_SUB_INT_FAST = 24,
    _BINARY_OP_MUL_INT_FAST = 25,

    // Binary operations - specialized float
    _BINARY_OP_ADD_FLOAT = 30,
    _BINARY_OP_SUB_FLOAT = 31,
    _BINARY_OP_MUL_FLOAT = 32,
    _BINARY_OP_DIV_FLOAT = 33,

    // Binary operations - specialized str
    _BINARY_OP_ADD_STR = 40,
    _BINARY_OP_MUL_STR_INT = 41,

    // Comparison operations
    _COMPARE_OP = 50,
    _COMPARE_OP_INT = 51,
    _COMPARE_OP_FLOAT = 52,
    _COMPARE_OP_STR = 53,

    // Subscript operations
    _BINARY_SUBSCR = 60,
    _BINARY_SUBSCR_LIST = 61,
    _BINARY_SUBSCR_TUPLE = 62,
    _BINARY_SUBSCR_DICT = 63,
    _BINARY_SUBSCR_STR = 64,
    _STORE_SUBSCR = 65,
    _STORE_SUBSCR_LIST = 66,
    _STORE_SUBSCR_DICT = 67,

    // Attribute access
    _LOAD_ATTR = 70,
    _LOAD_ATTR_INSTANCE = 71,
    _LOAD_ATTR_MODULE = 72,
    _LOAD_ATTR_CLASS = 73,
    _LOAD_ATTR_SLOT = 74,
    _STORE_ATTR = 75,
    _STORE_ATTR_INSTANCE = 76,
    _STORE_ATTR_SLOT = 77,

    // Global/Name access
    _LOAD_GLOBAL = 80,
    _LOAD_GLOBAL_MODULE = 81,
    _LOAD_GLOBAL_BUILTINS = 82,
    _STORE_GLOBAL = 83,
    _LOAD_NAME = 84,
    _STORE_NAME = 85,

    // Control flow
    _JUMP = 90,
    _JUMP_IF_TRUE = 91,
    _JUMP_IF_FALSE = 92,
    _POP_JUMP_IF_TRUE = 93,
    _POP_JUMP_IF_FALSE = 94,
    _FOR_ITER = 95,
    _FOR_ITER_LIST = 96,
    _FOR_ITER_TUPLE = 97,
    _FOR_ITER_RANGE = 98,

    // Call operations
    _CALL = 100,
    _CALL_BUILTIN_O = 101,
    _CALL_BUILTIN_FAST = 102,
    _CALL_PY_SIMPLE = 103,
    _CALL_PY_GENERAL = 104,
    _CALL_METHOD = 105,
    _RETURN_VALUE = 106,

    // Container operations
    _BUILD_LIST = 110,
    _BUILD_TUPLE = 111,
    _BUILD_SET = 112,
    _BUILD_MAP = 113,
    _LIST_APPEND = 114,
    _SET_ADD = 115,
    _MAP_ADD = 116,

    // Unary operations
    _UNARY_NEGATIVE = 120,
    _UNARY_NOT = 121,
    _UNARY_INVERT = 122,
    _UNARY_NEGATIVE_INT = 123,
    _UNARY_NEGATIVE_FLOAT = 124,

    // Guard operations
    _GUARD_TYPE_INT = 130,
    _GUARD_TYPE_FLOAT = 131,
    _GUARD_TYPE_STR = 132,
    _GUARD_TYPE_LIST = 133,
    _GUARD_TYPE_TUPLE = 134,
    _GUARD_TYPE_DICT = 135,
    _GUARD_NOT_NONE = 136,
    _GUARD_GLOBALS_VERSION = 137,
    _GUARD_BUILTINS_VERSION = 138,

    // Deoptimization
    _DEOPT = 140,
    _EXIT_TRACE = 141,
    _ERROR_HANDLER = 142,

    // Tier 2 specific
    _SAVE_IP = 150,
    _RESUME = 151,
    _CHECK_VALIDITY = 152,
};

// ============================================================================
// Bytecode Translation
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
// Translation Tables
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

/// Type identifier
pub const TypeId = enum(u8) {
    unknown,
    int_type,
    float_type,
    str_type,
    bytes_type,
    list_type,
    tuple_type,
    dict_type,
    set_type,
    none_type,
    bool_type,
    object_type,
};

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

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the optimizer bytecodes module
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

test "bytecode translation" {
    const uops = translateBytecode(.LOAD_FAST);
    try std.testing.expectEqual(@as(usize, 1), uops.len);
    try std.testing.expectEqual(MicroOp._LOAD_FAST, uops[0].op);
    try std.testing.expectEqual(ArgSource.bytecode_arg, uops[0].arg_source);
}

test "specialization" {
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_INT, specialize(._BINARY_OP_ADD, .int_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_FLOAT, specialize(._BINARY_OP_ADD, .float_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD_STR, specialize(._BINARY_OP_ADD, .str_type));
    try std.testing.expectEqual(MicroOp._BINARY_OP_ADD, specialize(._BINARY_OP_ADD, .unknown));
}

test "guard for type" {
    try std.testing.expectEqual(MicroOp._GUARD_TYPE_INT, guardForType(.int_type).?);
    try std.testing.expectEqual(MicroOp._GUARD_TYPE_LIST, guardForType(.list_type).?);
    try std.testing.expect(guardForType(.unknown) == null);
}

test "micro-op properties" {
    const load_props = getMicroOpProps(._LOAD_FAST);
    try std.testing.expectEqual(@as(i8, 1), load_props.stack_effect);
    try std.testing.expect(load_props.has_arg);
    try std.testing.expect(!load_props.is_guard);

    const guard_props = getMicroOpProps(._GUARD_TYPE_INT);
    try std.testing.expectEqual(@as(i8, 0), guard_props.stack_effect);
    try std.testing.expect(guard_props.is_guard);
    try std.testing.expect(guard_props.can_deopt);
}

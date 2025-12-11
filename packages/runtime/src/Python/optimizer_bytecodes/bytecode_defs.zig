/// bytecode_defs - Bytecode and Micro-Op Definitions
/// Mirrors cpython/Python/optimizer_bytecodes.c
///
/// Defines bytecode opcodes and micro-operation opcodes for the trace optimizer.

const std = @import("std");

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

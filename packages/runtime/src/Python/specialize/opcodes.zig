/// opcodes - Specialized Opcode Definitions
/// All specialized opcode variants and context structures.

const std = @import("std");
const types = @import("types.zig");

pub const TypeId = types.TypeId;
pub const CacheEntry = types.CacheEntry;

// ============================================================================
// Specialized Opcodes
// ============================================================================

/// Specialized opcode variants
pub const SpecializedOp = enum(u8) {
    // Load attr specializations
    LOAD_ATTR_INSTANCE_VALUE = 100,
    LOAD_ATTR_MODULE = 101,
    LOAD_ATTR_WITH_HINT = 102,
    LOAD_ATTR_SLOT = 103,
    LOAD_ATTR_CLASS = 104,
    LOAD_ATTR_PROPERTY = 105,
    LOAD_ATTR_GETATTRIBUTE_OVERRIDDEN = 106,
    LOAD_ATTR_METHOD_WITH_VALUES = 107,
    LOAD_ATTR_METHOD_NO_DICT = 108,
    LOAD_ATTR_METHOD_LAZY_DICT = 109,
    LOAD_ATTR_NONDESCRIPTOR_WITH_VALUES = 110,
    LOAD_ATTR_NONDESCRIPTOR_NO_DICT = 111,

    // Store attr specializations
    STORE_ATTR_INSTANCE_VALUE = 120,
    STORE_ATTR_WITH_HINT = 121,
    STORE_ATTR_SLOT = 122,

    // Binary op specializations
    BINARY_OP_ADD_INT = 130,
    BINARY_OP_ADD_FLOAT = 131,
    BINARY_OP_ADD_UNICODE = 132,
    BINARY_OP_SUBTRACT_INT = 133,
    BINARY_OP_SUBTRACT_FLOAT = 134,
    BINARY_OP_MULTIPLY_INT = 135,
    BINARY_OP_MULTIPLY_FLOAT = 136,
    BINARY_OP_INPLACE_ADD_UNICODE = 137,

    // Compare specializations
    COMPARE_OP_INT = 140,
    COMPARE_OP_FLOAT = 141,
    COMPARE_OP_STR = 142,

    // Subscript specializations
    BINARY_SUBSCR_LIST_INT = 150,
    BINARY_SUBSCR_TUPLE_INT = 151,
    BINARY_SUBSCR_DICT = 152,
    BINARY_SUBSCR_STR_INT = 153,
    STORE_SUBSCR_LIST_INT = 154,
    STORE_SUBSCR_DICT = 155,

    // Call specializations
    CALL_PY_EXACT_ARGS = 160,
    CALL_PY_WITH_DEFAULTS = 161,
    CALL_PY_GENERAL = 162,
    CALL_BUILTIN_CLASS = 163,
    CALL_BUILTIN_O = 164,
    CALL_BUILTIN_FAST = 165,
    CALL_BUILTIN_FAST_WITH_KEYWORDS = 166,
    CALL_LEN = 167,
    CALL_ISINSTANCE = 168,
    CALL_METHOD_DESCRIPTOR_O = 169,
    CALL_METHOD_DESCRIPTOR_FAST = 170,
    CALL_METHOD_DESCRIPTOR_NOARGS = 171,
    CALL_ALLOC_AND_ENTER_INIT = 172,
    CALL_BOUND_METHOD_EXACT_ARGS = 173,

    // Unpack specializations
    UNPACK_SEQUENCE_TWO_TUPLE = 180,
    UNPACK_SEQUENCE_TUPLE = 181,
    UNPACK_SEQUENCE_LIST = 182,

    // For iter specializations
    FOR_ITER_LIST = 190,
    FOR_ITER_TUPLE = 191,
    FOR_ITER_RANGE = 192,
    FOR_ITER_GEN = 193,

    // To bool specializations
    TO_BOOL_BOOL = 200,
    TO_BOOL_INT = 201,
    TO_BOOL_STR = 202,
    TO_BOOL_NONE = 203,
    TO_BOOL_LIST = 204,
    TO_BOOL_ALWAYS_TRUE = 205,

    // Contains specializations
    CONTAINS_OP_SET = 210,
    CONTAINS_OP_DICT = 211,

    // Load global specializations
    LOAD_GLOBAL_MODULE = 220,
    LOAD_GLOBAL_BUILTIN = 221,

    // Send specializations
    SEND_GEN = 230,

    // Generic (not specialized)
    GENERIC = 255,
};

/// Specialization context
pub const SpecializationContext = struct {
    /// Instruction pointer
    ip: u32,
    /// Original opcode
    opcode: u8,
    /// Operand
    oparg: u32,
    /// Cache pointer
    cache: ?*CacheEntry,
    /// Left operand type (for binary ops)
    lhs_type: TypeId = .unknown,
    /// Right operand type (for binary ops)
    rhs_type: TypeId = .unknown,
    /// Object type (for attr access)
    obj_type: TypeId = .unknown,
};

// ============================================================================
// Code Unit
// ============================================================================

/// Code unit (opcode + arg)
pub const CodeUnit = packed struct {
    op: u8,
    arg: u8,
};

/// Get number of cache entries for opcode
pub fn getOpcodeCaches(opcode: u8) u8 {
    return switch (opcode) {
        // LOAD_ATTR
        106 => 9,
        // STORE_ATTR
        95 => 4,
        // LOAD_GLOBAL
        116 => 4,
        // BINARY_OP
        122 => 1,
        // COMPARE_OP
        107 => 1,
        // BINARY_SUBSCR
        25 => 1,
        // STORE_SUBSCR
        60 => 1,
        // CALL
        171 => 3,
        // FOR_ITER
        68 => 1,
        // JUMP_BACKWARD
        140 => 1,
        // POP_JUMP_IF variants
        114, 115, 128, 129 => 1,
        else => 0,
    };
}

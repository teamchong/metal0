/// Optimizer Type Definitions
/// Core types for bytecode optimization and micro-ops

const std = @import("std");

/// Micro-operation (internal representation)
pub const MicroOp = struct {
    /// Opcode
    opcode: UopOpcode,
    /// Operand A
    oparg_a: u32 = 0,
    /// Operand B
    oparg_b: u32 = 0,
    /// Target (for jumps)
    target: u32 = 0,
    /// Source location
    lineno: i32 = 0,
};

/// Micro-op opcodes
pub const UopOpcode = enum(u16) {
    // Stack operations
    UOP_NOP = 0,
    UOP_LOAD_FAST = 1,
    UOP_STORE_FAST = 2,
    UOP_LOAD_CONST = 3,
    UOP_COPY = 4,
    UOP_SWAP = 5,
    UOP_POP_TOP = 6,

    // Binary operations
    UOP_BINARY_ADD = 10,
    UOP_BINARY_SUB = 11,
    UOP_BINARY_MUL = 12,
    UOP_BINARY_DIV = 13,
    UOP_BINARY_MOD = 14,

    // Specialized operations
    UOP_BINARY_ADD_INT = 20,
    UOP_BINARY_SUB_INT = 21,
    UOP_BINARY_MUL_INT = 22,
    UOP_BINARY_ADD_FLOAT = 23,
    UOP_BINARY_SUB_FLOAT = 24,
    UOP_BINARY_MUL_FLOAT = 25,

    // Comparison
    UOP_COMPARE_EQ = 30,
    UOP_COMPARE_NE = 31,
    UOP_COMPARE_LT = 32,
    UOP_COMPARE_LE = 33,
    UOP_COMPARE_GT = 34,
    UOP_COMPARE_GE = 35,

    // Control flow
    UOP_JUMP = 40,
    UOP_JUMP_IF_TRUE = 41,
    UOP_JUMP_IF_FALSE = 42,
    UOP_CALL = 43,
    UOP_RETURN = 44,

    // Guards
    UOP_GUARD_TYPE = 50,
    UOP_GUARD_VALUE = 51,
    UOP_GUARD_NOT_NONE = 52,
    UOP_GUARD_IS_TRUE = 53,
    UOP_GUARD_IS_FALSE = 54,

    // Deoptimization
    UOP_DEOPT = 60,
    UOP_EXIT_TRACE = 61,

    // Attribute access
    UOP_LOAD_ATTR = 70,
    UOP_STORE_ATTR = 71,

    // Container operations
    UOP_LOAD_SUBSCR = 80,
    UOP_STORE_SUBSCR = 81,
    UOP_BUILD_LIST = 82,
    UOP_BUILD_TUPLE = 83,
    UOP_BUILD_SET = 84,
    UOP_BUILD_MAP = 85,
};

/// Observed type information
pub const TypeInfo = struct {
    /// Stack slot index
    slot: u32,
    /// Observed type
    type_id: TypeId,
    /// Confidence (0-100)
    confidence: u8 = 100,
    /// Times observed
    observed_count: u32 = 1,
};

/// Type identifiers
pub const TypeId = enum(u8) {
    unknown = 0,
    none_type = 1,
    bool_type = 2,
    int_type = 3,
    float_type = 4,
    str_type = 5,
    bytes_type = 6,
    list_type = 7,
    tuple_type = 8,
    dict_type = 9,
    set_type = 10,
    function_type = 11,
    method_type = 12,
    module_type = 13,
    class_type = 14,
    object_type = 15,
};

/// Guard condition
pub const Guard = struct {
    /// Guard type
    kind: GuardKind,
    /// Stack slot being guarded
    slot: u32,
    /// Expected value/type
    expected: u64,
    /// Deoptimization target
    deopt_target: u32,
};

/// Guard types
pub const GuardKind = enum(u8) {
    type_check,
    value_check,
    not_none,
    is_true,
    is_false,
    bounds_check,
    overflow_check,
};

/// Optimizer statistics
pub const OptimizerStats = struct {
    traces_started: u64 = 0,
    traces_completed: u64 = 0,
    traces_aborted: u64 = 0,
    traces_optimized: u64 = 0,
    traces_executed: u64 = 0,
    deoptimizations: u64 = 0,
    total_uops: u64 = 0,
};

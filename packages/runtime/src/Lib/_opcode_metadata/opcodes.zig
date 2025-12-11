/// _opcode_metadata/opcodes.zig - Python 3.12+ opcode definitions
/// Contains complete definitions for all standard Python bytecode opcodes,
/// organized by category (stack, unary, binary, load, store, jump, call, etc).

const types = @import("types.zig");

pub const OpcodeDef = types.OpcodeDef;
pub const OpcodeCategory = types.OpcodeCategory;
pub const OpcodeFlags = types.OpcodeFlags;
pub const StackEffect = types.StackEffect;

/// All Python 3.12+ opcodes organized by category
pub const opcodes = struct {
    // ========================================================================
    // Stack Manipulation
    // ========================================================================

    pub const POP_TOP = OpcodeDef{
        .code = 1,
        .name = "POP_TOP",
        .stack_effect = .{ .pop = 1 },
    };

    pub const PUSH_NULL = OpcodeDef{
        .code = 2,
        .name = "PUSH_NULL",
        .stack_effect = .{ .push = 1 },
    };

    pub const NOP = OpcodeDef{
        .code = 9,
        .name = "NOP",
    };

    pub const END_FOR = OpcodeDef{
        .code = 4,
        .name = "END_FOR",
        .stack_effect = .{ .pop = 1 },
    };

    // ========================================================================
    // Unary Operations
    // ========================================================================

    pub const UNARY_NEGATIVE = OpcodeDef{
        .code = 11,
        .name = "UNARY_NEGATIVE",
        .category = .unary,
    };

    pub const UNARY_NOT = OpcodeDef{
        .code = 12,
        .name = "UNARY_NOT",
        .category = .unary,
    };

    pub const UNARY_INVERT = OpcodeDef{
        .code = 15,
        .name = "UNARY_INVERT",
        .category = .unary,
    };

    // ========================================================================
    // Binary Operations
    // ========================================================================

    pub const BINARY_OP = OpcodeDef{
        .code = 122,
        .name = "BINARY_OP",
        .category = .binary,
        .flags = .{ .has_arg = true, .has_cache = true },
        .stack_effect = .{ .pop = 2, .push = 1 },
        .cache_entries = 1,
    };

    pub const BINARY_SUBSCR = OpcodeDef{
        .code = 25,
        .name = "BINARY_SUBSCR",
        .category = .binary,
        .flags = .{ .has_cache = true },
        .stack_effect = .{ .pop = 2, .push = 1 },
        .cache_entries = 1,
    };

    // ========================================================================
    // Store Operations
    // ========================================================================

    pub const STORE_SUBSCR = OpcodeDef{
        .code = 60,
        .name = "STORE_SUBSCR",
        .category = .store,
        .flags = .{ .has_cache = true },
        .stack_effect = .{ .pop = 3 },
        .cache_entries = 1,
    };

    pub const STORE_FAST = OpcodeDef{
        .code = 125,
        .name = "STORE_FAST",
        .category = .store,
        .flags = .{ .has_arg = true, .has_local = true },
        .stack_effect = .{ .pop = 1 },
    };

    pub const STORE_GLOBAL = OpcodeDef{
        .code = 97,
        .name = "STORE_GLOBAL",
        .category = .store,
        .flags = .{ .has_arg = true, .has_name = true },
        .stack_effect = .{ .pop = 1 },
    };

    pub const STORE_ATTR = OpcodeDef{
        .code = 95,
        .name = "STORE_ATTR",
        .category = .store,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .pop = 2 },
        .cache_entries = 4,
    };

    // ========================================================================
    // Load Operations
    // ========================================================================

    pub const LOAD_CONST = OpcodeDef{
        .code = 100,
        .name = "LOAD_CONST",
        .category = .load,
        .flags = .{ .has_arg = true, .has_const = true },
        .stack_effect = .{ .push = 1 },
    };

    pub const LOAD_NAME = OpcodeDef{
        .code = 101,
        .name = "LOAD_NAME",
        .category = .load,
        .flags = .{ .has_arg = true, .has_name = true },
        .stack_effect = .{ .push = 1 },
    };

    pub const LOAD_FAST = OpcodeDef{
        .code = 124,
        .name = "LOAD_FAST",
        .category = .load,
        .flags = .{ .has_arg = true, .has_local = true },
        .stack_effect = .{ .push = 1 },
    };

    pub const LOAD_GLOBAL = OpcodeDef{
        .code = 116,
        .name = "LOAD_GLOBAL",
        .category = .load,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .push = 1, .varies = true },
        .cache_entries = 4,
    };

    pub const LOAD_ATTR = OpcodeDef{
        .code = 106,
        .name = "LOAD_ATTR",
        .category = .load,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .varies = true },
        .cache_entries = 9,
    };

    // ========================================================================
    // Build Operations
    // ========================================================================

    pub const BUILD_LIST = OpcodeDef{
        .code = 103,
        .name = "BUILD_LIST",
        .flags = .{ .has_arg = true },
        .stack_effect = .{ .varies = true },
    };

    pub const BUILD_TUPLE = OpcodeDef{
        .code = 102,
        .name = "BUILD_TUPLE",
        .flags = .{ .has_arg = true },
        .stack_effect = .{ .varies = true },
    };

    pub const BUILD_SET = OpcodeDef{
        .code = 104,
        .name = "BUILD_SET",
        .flags = .{ .has_arg = true },
        .stack_effect = .{ .varies = true },
    };

    pub const BUILD_MAP = OpcodeDef{
        .code = 105,
        .name = "BUILD_MAP",
        .flags = .{ .has_arg = true },
        .stack_effect = .{ .varies = true },
    };

    // ========================================================================
    // Jump Operations
    // ========================================================================

    pub const JUMP_FORWARD = OpcodeDef{
        .code = 110,
        .name = "JUMP_FORWARD",
        .category = .jump,
        .flags = .{ .has_arg = true, .has_jump = true },
    };

    pub const JUMP_BACKWARD = OpcodeDef{
        .code = 140,
        .name = "JUMP_BACKWARD",
        .category = .jump,
        .flags = .{ .has_arg = true, .has_jump = true },
    };

    pub const POP_JUMP_IF_FALSE = OpcodeDef{
        .code = 114,
        .name = "POP_JUMP_IF_FALSE",
        .category = .jump,
        .flags = .{ .has_arg = true, .has_jump = true },
        .stack_effect = .{ .pop = 1 },
    };

    pub const POP_JUMP_IF_TRUE = OpcodeDef{
        .code = 115,
        .name = "POP_JUMP_IF_TRUE",
        .category = .jump,
        .flags = .{ .has_arg = true, .has_jump = true },
        .stack_effect = .{ .pop = 1 },
    };

    // ========================================================================
    // Call Operations
    // ========================================================================

    pub const CALL = OpcodeDef{
        .code = 171,
        .name = "CALL",
        .category = .call,
        .flags = .{ .has_arg = true, .has_cache = true },
        .stack_effect = .{ .varies = true },
        .cache_entries = 3,
    };

    pub const RETURN_VALUE = OpcodeDef{
        .code = 83,
        .name = "RETURN_VALUE",
        .stack_effect = .{ .pop = 1 },
    };

    pub const RETURN_CONST = OpcodeDef{
        .code = 121,
        .name = "RETURN_CONST",
        .flags = .{ .has_arg = true, .has_const = true },
    };

    // ========================================================================
    // Comparison
    // ========================================================================

    pub const COMPARE_OP = OpcodeDef{
        .code = 107,
        .name = "COMPARE_OP",
        .category = .compare,
        .flags = .{ .has_arg = true, .has_cache = true },
        .stack_effect = .{ .pop = 2, .push = 1 },
        .cache_entries = 1,
    };

    // ========================================================================
    // Import
    // ========================================================================

    pub const IMPORT_NAME = OpcodeDef{
        .code = 108,
        .name = "IMPORT_NAME",
        .category = .import_op,
        .flags = .{ .has_arg = true, .has_name = true },
        .stack_effect = .{ .pop = 2, .push = 1 },
    };

    pub const IMPORT_FROM = OpcodeDef{
        .code = 109,
        .name = "IMPORT_FROM",
        .category = .import_op,
        .flags = .{ .has_arg = true, .has_name = true },
        .stack_effect = .{ .push = 1 },
    };

    // ========================================================================
    // Generator/Coroutine
    // ========================================================================

    pub const YIELD_VALUE = OpcodeDef{
        .code = 86,
        .name = "YIELD_VALUE",
        .category = .generator,
    };

    pub const GET_AWAITABLE = OpcodeDef{
        .code = 131,
        .name = "GET_AWAITABLE",
        .category = .coroutine,
        .flags = .{ .has_arg = true },
    };

    pub const SEND = OpcodeDef{
        .code = 132,
        .name = "SEND",
        .category = .generator,
        .flags = .{ .has_arg = true, .has_cache = true },
        .cache_entries = 1,
    };

    // ========================================================================
    // Exception Handling
    // ========================================================================

    pub const RAISE_VARARGS = OpcodeDef{
        .code = 130,
        .name = "RAISE_VARARGS",
        .category = .exception,
        .flags = .{ .has_arg = true },
        .stack_effect = .{ .varies = true },
    };

    pub const PUSH_EXC_INFO = OpcodeDef{
        .code = 35,
        .name = "PUSH_EXC_INFO",
        .category = .exception,
        .stack_effect = .{ .push = 1 },
    };

    pub const POP_EXCEPT = OpcodeDef{
        .code = 89,
        .name = "POP_EXCEPT",
        .category = .exception,
        .stack_effect = .{ .pop = 1 },
    };
};

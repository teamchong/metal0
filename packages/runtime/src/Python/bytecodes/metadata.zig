/// Opcode Metadata and Information Tables
/// Contains opcode metadata structures and initialization

const constants = @import("constants.zig");

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
        return (self.flags & constants.OPCODE_HAS_ARG) != 0;
    }

    /// Check if opcode is a jump
    pub fn isJump(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_IS_JUMP) != 0;
    }

    /// Check if opcode is a relative jump
    pub fn isRelativeJump(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_REL_JUMP) != 0;
    }

    /// Check if opcode has local variable argument
    pub fn hasLocal(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_HAS_LOCAL) != 0;
    }

    /// Check if opcode has free variable argument
    pub fn hasFree(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_HAS_FREE) != 0;
    }

    /// Check if opcode has constant argument
    pub fn hasConst(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_HAS_CONST) != 0;
    }

    /// Check if opcode has name argument
    pub fn hasName(self: *const OpcodeInfo) bool {
        return (self.flags & constants.OPCODE_HAS_NAME) != 0;
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
    table[constants.NOP] = .{ .name = "NOP", .stack_effect = 0, .flags = 0 };
    table[constants.POP_TOP] = .{ .name = "POP_TOP", .stack_effect = -1, .flags = 0 };
    table[constants.PUSH_NULL] = .{ .name = "PUSH_NULL", .stack_effect = 1, .flags = 0 };
    table[constants.END_FOR] = .{ .name = "END_FOR", .stack_effect = -2, .flags = 0 };

    // Unary operations
    table[constants.UNARY_NEGATIVE] = .{ .name = "UNARY_NEGATIVE", .stack_effect = 0, .flags = 0 };
    table[constants.UNARY_NOT] = .{ .name = "UNARY_NOT", .stack_effect = 0, .flags = 0 };
    table[constants.UNARY_INVERT] = .{ .name = "UNARY_INVERT", .stack_effect = 0, .flags = 0 };

    // Binary operations
    table[constants.BINARY_OP] = .{ .name = "BINARY_OP", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG, .cache_entries = 1 };
    table[constants.BINARY_SUBSCR] = .{ .name = "BINARY_SUBSCR", .stack_effect = -1, .flags = 0, .cache_entries = 1 };
    table[constants.STORE_SUBSCR] = .{ .name = "STORE_SUBSCR", .stack_effect = -3, .flags = 0, .cache_entries = 1 };
    table[constants.DELETE_SUBSCR] = .{ .name = "DELETE_SUBSCR", .stack_effect = -2, .flags = 0 };

    // Load/Store operations
    table[constants.LOAD_CONST] = .{ .name = "LOAD_CONST", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_CONST };
    table[constants.LOAD_NAME] = .{ .name = "LOAD_NAME", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };
    table[constants.STORE_NAME] = .{ .name = "STORE_NAME", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };
    table[constants.DELETE_NAME] = .{ .name = "DELETE_NAME", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };

    table[constants.LOAD_GLOBAL] = .{ .name = "LOAD_GLOBAL", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME, .cache_entries = 4 };
    table[constants.STORE_GLOBAL] = .{ .name = "STORE_GLOBAL", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };
    table[constants.DELETE_GLOBAL] = .{ .name = "DELETE_GLOBAL", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };

    table[constants.LOAD_FAST] = .{ .name = "LOAD_FAST", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_LOCAL };
    table[constants.LOAD_FAST_CHECK] = .{ .name = "LOAD_FAST_CHECK", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_LOCAL };
    table[constants.LOAD_FAST_AND_CLEAR] = .{ .name = "LOAD_FAST_AND_CLEAR", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_LOCAL };
    table[constants.STORE_FAST] = .{ .name = "STORE_FAST", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_LOCAL };
    table[constants.DELETE_FAST] = .{ .name = "DELETE_FAST", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_LOCAL };

    table[constants.LOAD_DEREF] = .{ .name = "LOAD_DEREF", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_FREE };
    table[constants.STORE_DEREF] = .{ .name = "STORE_DEREF", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_FREE };
    table[constants.DELETE_DEREF] = .{ .name = "DELETE_DEREF", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_FREE };

    // Attribute access
    table[constants.LOAD_ATTR] = .{ .name = "LOAD_ATTR", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME, .cache_entries = 9 };
    table[constants.STORE_ATTR] = .{ .name = "STORE_ATTR", .stack_effect = -2, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME, .cache_entries = 4 };
    table[constants.DELETE_ATTR] = .{ .name = "DELETE_ATTR", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };

    // Build operations
    table[constants.BUILD_TUPLE] = .{ .name = "BUILD_TUPLE", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG }; // stack effect varies
    table[constants.BUILD_LIST] = .{ .name = "BUILD_LIST", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };
    table[constants.BUILD_SET] = .{ .name = "BUILD_SET", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };
    table[constants.BUILD_MAP] = .{ .name = "BUILD_MAP", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };
    table[constants.BUILD_STRING] = .{ .name = "BUILD_STRING", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };
    table[constants.BUILD_SLICE] = .{ .name = "BUILD_SLICE", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Jump operations
    table[constants.JUMP_FORWARD] = .{ .name = "JUMP_FORWARD", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP | constants.OPCODE_REL_JUMP };
    table[constants.JUMP_BACKWARD] = .{ .name = "JUMP_BACKWARD", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP | constants.OPCODE_REL_JUMP };
    table[constants.JUMP_BACKWARD_NO_INTERRUPT] = .{ .name = "JUMP_BACKWARD_NO_INTERRUPT", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP | constants.OPCODE_REL_JUMP };
    table[constants.POP_JUMP_IF_FALSE] = .{ .name = "POP_JUMP_IF_FALSE", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP };
    table[constants.POP_JUMP_IF_TRUE] = .{ .name = "POP_JUMP_IF_TRUE", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP };
    table[constants.JUMP_IF_FALSE_OR_POP] = .{ .name = "JUMP_IF_FALSE_OR_POP", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP };
    table[constants.JUMP_IF_TRUE_OR_POP] = .{ .name = "JUMP_IF_TRUE_OR_POP", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP };

    // Comparison
    table[constants.COMPARE_OP] = .{ .name = "COMPARE_OP", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG, .cache_entries = 1 };

    // Return/Yield
    table[constants.RETURN_VALUE] = .{ .name = "RETURN_VALUE", .stack_effect = -1, .flags = 0 };
    table[constants.RETURN_CONST] = .{ .name = "RETURN_CONST", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_CONST };
    table[constants.YIELD_VALUE] = .{ .name = "YIELD_VALUE", .stack_effect = 0, .flags = 0 };

    // Iterator
    table[constants.GET_ITER] = .{ .name = "GET_ITER", .stack_effect = 0, .flags = 0 };
    table[constants.FOR_ITER] = .{ .name = "FOR_ITER", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_IS_JUMP, .cache_entries = 1 };

    // Call
    table[constants.CALL] = .{ .name = "CALL", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG, .cache_entries = 3 };
    table[constants.CALL_FUNCTION_EX] = .{ .name = "CALL_FUNCTION_EX", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG };
    table[constants.KW_NAMES] = .{ .name = "KW_NAMES", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_CONST };

    // Functions
    table[constants.MAKE_FUNCTION] = .{ .name = "MAKE_FUNCTION", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Imports
    table[constants.IMPORT_NAME] = .{ .name = "IMPORT_NAME", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };
    table[constants.IMPORT_FROM] = .{ .name = "IMPORT_FROM", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG | constants.OPCODE_HAS_NAME };

    // Unpack
    table[constants.UNPACK_SEQUENCE] = .{ .name = "UNPACK_SEQUENCE", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG, .cache_entries = 1 };
    table[constants.UNPACK_EX] = .{ .name = "UNPACK_EX", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Exception handling
    table[constants.RAISE_VARARGS] = .{ .name = "RAISE_VARARGS", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };
    table[constants.POP_EXCEPT] = .{ .name = "POP_EXCEPT", .stack_effect = -1, .flags = 0 };
    table[constants.PUSH_EXC_INFO] = .{ .name = "PUSH_EXC_INFO", .stack_effect = 1, .flags = 0 };
    table[constants.CHECK_EXC_MATCH] = .{ .name = "CHECK_EXC_MATCH", .stack_effect = 0, .flags = 0 };

    // Extended arg
    table[constants.EXTENDED_ARG] = .{ .name = "EXTENDED_ARG", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Comprehensions
    table[constants.LIST_APPEND] = .{ .name = "LIST_APPEND", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG };
    table[constants.SET_ADD] = .{ .name = "SET_ADD", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG };
    table[constants.MAP_ADD] = .{ .name = "MAP_ADD", .stack_effect = -2, .flags = constants.OPCODE_HAS_ARG };

    // Copy/Swap
    table[constants.COPY] = .{ .name = "COPY", .stack_effect = 1, .flags = constants.OPCODE_HAS_ARG };
    table[constants.SWAP] = .{ .name = "SWAP", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Resume
    table[constants.RESUME] = .{ .name = "RESUME", .stack_effect = 0, .flags = constants.OPCODE_HAS_ARG };

    // Pattern matching
    table[constants.MATCH_MAPPING] = .{ .name = "MATCH_MAPPING", .stack_effect = 1, .flags = 0 };
    table[constants.MATCH_SEQUENCE] = .{ .name = "MATCH_SEQUENCE", .stack_effect = 1, .flags = 0 };
    table[constants.MATCH_KEYS] = .{ .name = "MATCH_KEYS", .stack_effect = 1, .flags = 0 };
    table[constants.MATCH_CLASS] = .{ .name = "MATCH_CLASS", .stack_effect = -1, .flags = constants.OPCODE_HAS_ARG };

    return table;
}

/// Get opcode name
pub fn opcodeName(opcode: u8) []const u8 {
    return OPCODE_TABLE[opcode].name;
}

/// Get number of inline cache entries for opcode
pub fn cacheEntries(opcode: u8) u8 {
    return OPCODE_TABLE[opcode].cache_entries;
}

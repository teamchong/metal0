/// _opcode_metadata - Python Bytecode Opcode Metadata
/// Mirrors cpython/Lib/_opcode_metadata.py
///
/// Metadata about Python bytecode opcodes including stack effects,
/// instruction formats, and specialization information.
/// Used by the dis module and other bytecode analysis tools.

const std = @import("std");

// ============================================================================
// Opcode Categories
// ============================================================================

/// Opcode categories
pub const OpcodeCategory = enum {
    pseudo, // Pseudo instructions (not real opcodes)
    specialized, // Specialized/optimized versions
    cache, // Cache entries
    general, // General instructions
    jump, // Jump instructions
    load, // Load operations
    store, // Store operations
    call, // Call operations
    binary, // Binary operations
    unary, // Unary operations
    compare, // Comparison operations
    import_op, // Import operations
    exception, // Exception handling
    generator, // Generator operations
    coroutine, // Coroutine operations
    intrinsic, // Intrinsic operations
};

// ============================================================================
// Opcode Flags
// ============================================================================

/// Opcode flags
pub const OpcodeFlags = packed struct {
    has_arg: bool = false, // Has an argument
    has_const: bool = false, // Argument is a constant index
    has_name: bool = false, // Argument is a name index
    has_local: bool = false, // Argument is a local variable index
    has_free: bool = false, // Argument is a free variable index
    has_jump: bool = false, // Has a jump target
    has_cache: bool = false, // Has cache entries
    is_pseudo: bool = false, // Is a pseudo instruction
};

// ============================================================================
// Stack Effect
// ============================================================================

/// Stack effect of an instruction
pub const StackEffect = struct {
    /// Number of items popped
    pop: i8 = 0,
    /// Number of items pushed
    push: i8 = 0,
    /// Whether effect varies with argument
    varies: bool = false,

    /// Net stack effect
    pub fn net(self: StackEffect) i8 {
        return self.push - self.pop;
    }
};

// ============================================================================
// Opcode Definition
// ============================================================================

/// Complete opcode definition
pub const OpcodeDef = struct {
    /// Opcode value (0-255)
    code: u8,
    /// Mnemonic name
    name: []const u8,
    /// Category
    category: OpcodeCategory = .general,
    /// Flags
    flags: OpcodeFlags = .{},
    /// Stack effect
    stack_effect: StackEffect = .{},
    /// Number of cache entries
    cache_entries: u8 = 0,
    /// Base opcode (for specialized)
    base_opcode: ?u8 = null,
};

// ============================================================================
// Python 3.12+ Opcodes (partial list of important ones)
// ============================================================================

pub const opcodes = struct {
    // Stack manipulation
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

    // Unary operations
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

    // Binary operations
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

    // Store/Load operations
    pub const STORE_SUBSCR = OpcodeDef{
        .code = 60,
        .name = "STORE_SUBSCR",
        .category = .store,
        .flags = .{ .has_cache = true },
        .stack_effect = .{ .pop = 3 },
        .cache_entries = 1,
    };

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

    pub const STORE_FAST = OpcodeDef{
        .code = 125,
        .name = "STORE_FAST",
        .category = .store,
        .flags = .{ .has_arg = true, .has_local = true },
        .stack_effect = .{ .pop = 1 },
    };

    pub const LOAD_GLOBAL = OpcodeDef{
        .code = 116,
        .name = "LOAD_GLOBAL",
        .category = .load,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .push = 1, .varies = true },
        .cache_entries = 4,
    };

    pub const STORE_GLOBAL = OpcodeDef{
        .code = 97,
        .name = "STORE_GLOBAL",
        .category = .store,
        .flags = .{ .has_arg = true, .has_name = true },
        .stack_effect = .{ .pop = 1 },
    };

    pub const LOAD_ATTR = OpcodeDef{
        .code = 106,
        .name = "LOAD_ATTR",
        .category = .load,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .varies = true },
        .cache_entries = 9,
    };

    pub const STORE_ATTR = OpcodeDef{
        .code = 95,
        .name = "STORE_ATTR",
        .category = .store,
        .flags = .{ .has_arg = true, .has_name = true, .has_cache = true },
        .stack_effect = .{ .pop = 2 },
        .cache_entries = 4,
    };

    // Build operations
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

    // Jump operations
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

    // Call operations
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

    // Comparison
    pub const COMPARE_OP = OpcodeDef{
        .code = 107,
        .name = "COMPARE_OP",
        .category = .compare,
        .flags = .{ .has_arg = true, .has_cache = true },
        .stack_effect = .{ .pop = 2, .push = 1 },
        .cache_entries = 1,
    };

    // Import
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

    // Generator/Coroutine
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

    // Exception handling
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

// ============================================================================
// Lookup Functions
// ============================================================================

/// Get opcode by code
pub fn getOpcode(code: u8) ?OpcodeDef {
    // In a full implementation, this would be a lookup table
    inline for (@typeInfo(opcodes).@"struct".decls) |decl| {
        const op = @field(opcodes, decl.name);
        if (@TypeOf(op) == OpcodeDef and op.code == code) {
            return op;
        }
    }
    return null;
}

/// Get opcode by name
pub fn getOpcodeByName(name: []const u8) ?OpcodeDef {
    inline for (@typeInfo(opcodes).@"struct".decls) |decl| {
        const op = @field(opcodes, decl.name);
        if (@TypeOf(op) == OpcodeDef and std.mem.eql(u8, op.name, name)) {
            return op;
        }
    }
    return null;
}

// ============================================================================
// Comparison Operations
// ============================================================================

/// Comparison operation codes (for COMPARE_OP)
pub const CompareOp = enum(u8) {
    lt = 0,
    le = 1,
    eq = 2,
    ne = 3,
    gt = 4,
    ge = 5,

    pub fn getName(self: CompareOp) []const u8 {
        return switch (self) {
            .lt => "<",
            .le => "<=",
            .eq => "==",
            .ne => "!=",
            .gt => ">",
            .ge => ">=",
        };
    }
};

// ============================================================================
// Binary Operations
// ============================================================================

/// Binary operation codes (for BINARY_OP)
pub const BinaryOp = enum(u8) {
    add = 0,
    and_ = 1,
    floor_divide = 2,
    lshift = 3,
    matmul = 4,
    multiply = 5,
    remainder = 6,
    or_ = 7,
    power = 8,
    rshift = 9,
    subtract = 10,
    true_divide = 11,
    xor = 12,
    inplace_add = 13,
    // ... more inplace operations

    pub fn getName(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .and_ => "&",
            .floor_divide => "//",
            .lshift => "<<",
            .matmul => "@",
            .multiply => "*",
            .remainder => "%",
            .or_ => "|",
            .power => "**",
            .rshift => ">>",
            .subtract => "-",
            .true_divide => "/",
            .xor => "^",
            .inplace_add => "+=",
        };
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _opcode_metadata module
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

test "opcode definition" {
    const load_const = opcodes.LOAD_CONST;
    try std.testing.expectEqual(@as(u8, 100), load_const.code);
    try std.testing.expectEqualStrings("LOAD_CONST", load_const.name);
    try std.testing.expect(load_const.flags.has_arg);
    try std.testing.expect(load_const.flags.has_const);
}

test "stack effect" {
    const pop_top = opcodes.POP_TOP;
    try std.testing.expectEqual(@as(i8, -1), pop_top.stack_effect.net());

    const push_null = opcodes.PUSH_NULL;
    try std.testing.expectEqual(@as(i8, 1), push_null.stack_effect.net());
}

test "compare op names" {
    try std.testing.expectEqualStrings("<", CompareOp.lt.getName());
    try std.testing.expectEqualStrings("==", CompareOp.eq.getName());
    try std.testing.expectEqualStrings("!=", CompareOp.ne.getName());
}

test "binary op names" {
    try std.testing.expectEqualStrings("+", BinaryOp.add.getName());
    try std.testing.expectEqualStrings("*", BinaryOp.multiply.getName());
    try std.testing.expectEqualStrings("//", BinaryOp.floor_divide.getName());
}

test "get opcode by code" {
    if (getOpcode(100)) |op| {
        try std.testing.expectEqualStrings("LOAD_CONST", op.name);
    } else {
        return error.TestFailed;
    }
}

test "get opcode by name" {
    if (getOpcodeByName("RETURN_VALUE")) |op| {
        try std.testing.expectEqual(@as(u8, 83), op.code);
    } else {
        return error.TestFailed;
    }
}

test "cache entries" {
    const load_global = opcodes.LOAD_GLOBAL;
    try std.testing.expectEqual(@as(u8, 4), load_global.cache_entries);

    const load_attr = opcodes.LOAD_ATTR;
    try std.testing.expectEqual(@as(u8, 9), load_attr.cache_entries);
}

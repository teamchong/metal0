/// opcode - Python Bytecode Opcodes
/// Mirrors cpython/Lib/opcode.py
///
/// Provides opcode constants and information for Python bytecode.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// First opcode with an argument
pub const HAVE_ARGUMENT: u8 = 90;

/// Number of opcodes
pub const NUM_OPCODES: usize = 256;

// ============================================================================
// Opcode Definitions (Python 3.12+)
// ============================================================================

pub const Opcode = enum(u8) {
    // Stack manipulation
    POP_TOP = 1,
    PUSH_NULL = 2,
    END_FOR = 4,
    END_SEND = 5,
    NOP = 9,

    // Unary operations
    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    // Binary operations (historic, kept for compatibility)
    BINARY_SUBSCR = 25,

    // Exception handling
    PUSH_EXC_INFO = 35,
    CHECK_EXC_MATCH = 36,
    CHECK_EG_MATCH = 37,

    // Data operations
    WITH_EXCEPT_START = 49,
    GET_AITER = 50,
    GET_ANEXT = 51,
    BEFORE_ASYNC_WITH = 52,
    BEFORE_WITH = 53,
    END_ASYNC_FOR = 54,
    CLEANUP_THROW = 55,

    // Subscript operations
    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    // Iterator
    GET_ITER = 68,
    GET_YIELD_FROM_ITER = 69,

    // Return
    RETURN_VALUE = 83,
    RETURN_CONST = 121,
    YIELD_VALUE = 86,

    // Exception
    SETUP_ANNOTATIONS = 85,
    POP_EXCEPT = 89,

    // Store/Delete
    STORE_NAME = 90,
    DELETE_NAME = 91,
    UNPACK_SEQUENCE = 92,
    FOR_ITER = 93,
    UNPACK_EX = 94,
    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,
    SWAP = 99,
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
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,
    IS_OP = 117,
    CONTAINS_OP = 118,
    RERAISE = 119,
    COPY = 120,

    // Binary op
    BINARY_OP = 122,

    // Send
    SEND = 132,

    // Load/Store
    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,
    LOAD_FAST_CHECK = 127,
    POP_JUMP_IF_NOT_NONE = 128,
    POP_JUMP_IF_NONE = 129,
    RAISE_VARARGS = 130,
    GET_AWAITABLE = 131,

    // Make
    MAKE_FUNCTION = 132,
    BUILD_SLICE = 133,
    JUMP_BACKWARD_NO_INTERRUPT = 134,
    MAKE_CELL = 135,
    LOAD_CLOSURE = 136,
    LOAD_DEREF = 137,
    STORE_DEREF = 138,
    DELETE_DEREF = 139,
    JUMP_BACKWARD = 140,
    LOAD_SUPER_ATTR = 141,
    CALL_FUNCTION_EX = 142,

    // Extended arg
    EXTENDED_ARG = 144,

    // List/Set/Map comprehension
    LIST_APPEND = 145,
    SET_ADD = 146,
    MAP_ADD = 147,
    COPY_FREE_VARS = 149,

    // Yield from
    YIELD_FROM = 150,

    // Resume
    RESUME = 151,

    // Match
    MATCH_CLASS = 152,

    // Format
    FORMAT_VALUE = 155,
    BUILD_CONST_KEY_MAP = 156,
    BUILD_STRING = 157,

    // Load method
    LOAD_METHOD = 160,

    // List extend
    LIST_EXTEND = 162,
    SET_UPDATE = 163,
    DICT_MERGE = 164,
    DICT_UPDATE = 165,

    // Call
    CALL = 171,
    KW_NAMES = 172,
    CALL_INTRINSIC_1 = 173,
    CALL_INTRINSIC_2 = 174,

    // Invalid
    CACHE = 0,

    pub fn getName(self: Opcode) []const u8 {
        return @tagName(self);
    }

    pub fn hasArg(self: Opcode) bool {
        return @intFromEnum(self) >= HAVE_ARGUMENT;
    }
};

// ============================================================================
// Opcode Maps
// ============================================================================

/// Map opcode name to value
pub const opmap = blk: {
    var map: [256]?[]const u8 = [_]?[]const u8{null} ** 256;
    for (std.enums.values(Opcode)) |op| {
        map[@intFromEnum(op)] = @tagName(op);
    }
    break :blk map;
};

/// Map opcode value to name
pub fn opname(code: u8) []const u8 {
    if (opmap[code]) |name| {
        return name;
    }
    return "<unknown>";
}

// ============================================================================
// Opcode Categories
// ============================================================================

/// Opcodes with relative jumps
pub const hasJrel = [_]u8{
    @intFromEnum(Opcode.JUMP_FORWARD),
    @intFromEnum(Opcode.FOR_ITER),
    @intFromEnum(Opcode.SEND),
};

/// Opcodes with absolute jumps
pub const hasJabs = [_]u8{
    @intFromEnum(Opcode.POP_JUMP_IF_FALSE),
    @intFromEnum(Opcode.POP_JUMP_IF_TRUE),
    @intFromEnum(Opcode.JUMP_BACKWARD),
    @intFromEnum(Opcode.POP_JUMP_IF_NOT_NONE),
    @intFromEnum(Opcode.POP_JUMP_IF_NONE),
};

/// Opcodes that access a local variable
pub const hasLocal = [_]u8{
    @intFromEnum(Opcode.LOAD_FAST),
    @intFromEnum(Opcode.STORE_FAST),
    @intFromEnum(Opcode.DELETE_FAST),
    @intFromEnum(Opcode.LOAD_FAST_CHECK),
};

/// Opcodes that access a constant
pub const hasConst = [_]u8{
    @intFromEnum(Opcode.LOAD_CONST),
    @intFromEnum(Opcode.RETURN_CONST),
    @intFromEnum(Opcode.KW_NAMES),
};

/// Opcodes that access a name
pub const hasName = [_]u8{
    @intFromEnum(Opcode.STORE_NAME),
    @intFromEnum(Opcode.DELETE_NAME),
    @intFromEnum(Opcode.LOAD_NAME),
    @intFromEnum(Opcode.STORE_ATTR),
    @intFromEnum(Opcode.DELETE_ATTR),
    @intFromEnum(Opcode.STORE_GLOBAL),
    @intFromEnum(Opcode.DELETE_GLOBAL),
    @intFromEnum(Opcode.LOAD_ATTR),
    @intFromEnum(Opcode.IMPORT_NAME),
    @intFromEnum(Opcode.IMPORT_FROM),
    @intFromEnum(Opcode.LOAD_GLOBAL),
    @intFromEnum(Opcode.LOAD_METHOD),
    @intFromEnum(Opcode.LOAD_SUPER_ATTR),
};

/// Opcodes that access a free variable
pub const hasFree = [_]u8{
    @intFromEnum(Opcode.LOAD_CLOSURE),
    @intFromEnum(Opcode.LOAD_DEREF),
    @intFromEnum(Opcode.STORE_DEREF),
    @intFromEnum(Opcode.DELETE_DEREF),
    @intFromEnum(Opcode.MAKE_CELL),
    @intFromEnum(Opcode.COPY_FREE_VARS),
};

/// Opcodes that compare
pub const hasCompare = [_]u8{
    @intFromEnum(Opcode.COMPARE_OP),
};

// ============================================================================
// Comparison Operations
// ============================================================================

pub const CmpOp = enum(u8) {
    LT = 0,
    LE = 1,
    EQ = 2,
    NE = 3,
    GT = 4,
    GE = 5,

    pub fn getSymbol(self: CmpOp) []const u8 {
        return switch (self) {
            .LT => "<",
            .LE => "<=",
            .EQ => "==",
            .NE => "!=",
            .GT => ">",
            .GE => ">=",
        };
    }
};

// ============================================================================
// Binary Operations
// ============================================================================

pub const BinaryOp = enum(u8) {
    ADD = 0,
    AND = 1,
    FLOOR_DIVIDE = 2,
    LSHIFT = 3,
    MATMUL = 4,
    MULTIPLY = 5,
    REMAINDER = 6,
    OR = 7,
    POWER = 8,
    RSHIFT = 9,
    SUBTRACT = 10,
    TRUE_DIVIDE = 11,
    XOR = 12,
    INPLACE_ADD = 13,
    INPLACE_AND = 14,
    INPLACE_FLOOR_DIVIDE = 15,
    INPLACE_LSHIFT = 16,
    INPLACE_MATMUL = 17,
    INPLACE_MULTIPLY = 18,
    INPLACE_REMAINDER = 19,
    INPLACE_OR = 20,
    INPLACE_POWER = 21,
    INPLACE_RSHIFT = 22,
    INPLACE_SUBTRACT = 23,
    INPLACE_TRUE_DIVIDE = 24,
    INPLACE_XOR = 25,

    pub fn getSymbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .ADD => "+",
            .AND => "&",
            .FLOOR_DIVIDE => "//",
            .LSHIFT => "<<",
            .MATMUL => "@",
            .MULTIPLY => "*",
            .REMAINDER => "%",
            .OR => "|",
            .POWER => "**",
            .RSHIFT => ">>",
            .SUBTRACT => "-",
            .TRUE_DIVIDE => "/",
            .XOR => "^",
            .INPLACE_ADD => "+=",
            .INPLACE_AND => "&=",
            .INPLACE_FLOOR_DIVIDE => "//=",
            .INPLACE_LSHIFT => "<<=",
            .INPLACE_MATMUL => "@=",
            .INPLACE_MULTIPLY => "*=",
            .INPLACE_REMAINDER => "%=",
            .INPLACE_OR => "|=",
            .INPLACE_POWER => "**=",
            .INPLACE_RSHIFT => ">>=",
            .INPLACE_SUBTRACT => "-=",
            .INPLACE_TRUE_DIVIDE => "/=",
            .INPLACE_XOR => "^=",
        };
    }
};

// ============================================================================
// Stack Effect
// ============================================================================

/// Get stack effect of an opcode
pub fn stackEffect(opcode: u8, arg: ?u32) i32 {
    const op: Opcode = @enumFromInt(opcode);
    return switch (op) {
        .POP_TOP => -1,
        .PUSH_NULL => 1,
        .NOP => 0,
        .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
        .BINARY_SUBSCR => -1,
        .STORE_SUBSCR => -3,
        .DELETE_SUBSCR => -2,
        .GET_ITER => 0,
        .RETURN_VALUE => -1,
        .RETURN_CONST => 0,
        .YIELD_VALUE => 0,
        .POP_EXCEPT => -1,
        .STORE_NAME => -1,
        .DELETE_NAME => 0,
        .LOAD_CONST => 1,
        .LOAD_NAME => 1,
        .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => blk: {
            const a: i32 = @intCast(arg orelse 0);
            break :blk 1 - a;
        },
        .BUILD_MAP => blk: {
            const a: i32 = @intCast(arg orelse 0);
            break :blk 1 - 2 * a;
        },
        .LOAD_ATTR => 0,
        .COMPARE_OP => -1,
        .IMPORT_NAME => -1,
        .IMPORT_FROM => 1,
        .LOAD_GLOBAL => 1,
        .LOAD_FAST => 1,
        .STORE_FAST => -1,
        .DELETE_FAST => 0,
        .CALL => blk: {
            const a: i32 = @intCast(arg orelse 0);
            break :blk -a;
        },
        .BINARY_OP => -1,
        else => 0,
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the opcode module
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

test "HAVE_ARGUMENT constant" {
    try std.testing.expectEqual(@as(u8, 90), HAVE_ARGUMENT);
}

test "opcode values" {
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Opcode.POP_TOP));
    try std.testing.expectEqual(@as(u8, 100), @intFromEnum(Opcode.LOAD_CONST));
    try std.testing.expectEqual(@as(u8, 83), @intFromEnum(Opcode.RETURN_VALUE));
}

test "opcode hasArg" {
    try std.testing.expect(!Opcode.POP_TOP.hasArg());
    try std.testing.expect(Opcode.LOAD_CONST.hasArg());
    try std.testing.expect(Opcode.LOAD_FAST.hasArg());
}

test "opcode getName" {
    try std.testing.expectEqualStrings("POP_TOP", Opcode.POP_TOP.getName());
    try std.testing.expectEqualStrings("LOAD_CONST", Opcode.LOAD_CONST.getName());
}

test "opname function" {
    try std.testing.expectEqualStrings("POP_TOP", opname(1));
    try std.testing.expectEqualStrings("LOAD_CONST", opname(100));
}

test "CmpOp symbols" {
    try std.testing.expectEqualStrings("<", CmpOp.LT.getSymbol());
    try std.testing.expectEqualStrings("==", CmpOp.EQ.getSymbol());
    try std.testing.expectEqualStrings("!=", CmpOp.NE.getSymbol());
}

test "BinaryOp symbols" {
    try std.testing.expectEqualStrings("+", BinaryOp.ADD.getSymbol());
    try std.testing.expectEqualStrings("*", BinaryOp.MULTIPLY.getSymbol());
    try std.testing.expectEqualStrings("//", BinaryOp.FLOOR_DIVIDE.getSymbol());
    try std.testing.expectEqualStrings("+=", BinaryOp.INPLACE_ADD.getSymbol());
}

test "stackEffect" {
    try std.testing.expectEqual(@as(i32, -1), stackEffect(@intFromEnum(Opcode.POP_TOP), null));
    try std.testing.expectEqual(@as(i32, 1), stackEffect(@intFromEnum(Opcode.PUSH_NULL), null));
    try std.testing.expectEqual(@as(i32, 1), stackEffect(@intFromEnum(Opcode.LOAD_CONST), null));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(@intFromEnum(Opcode.STORE_FAST), null));
}

test "hasLocal contains LOAD_FAST" {
    var found = false;
    for (hasLocal) |op| {
        if (op == @intFromEnum(Opcode.LOAD_FAST)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "hasConst contains LOAD_CONST" {
    var found = false;
    for (hasConst) |op| {
        if (op == @intFromEnum(Opcode.LOAD_CONST)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

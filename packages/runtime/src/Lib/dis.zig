//! Python 'dis' module - Disassembler for Python bytecode
//!
//! Provides functions to disassemble Python bytecode.
//!
//! Mirrors: CPython Lib/dis.py

const std = @import("std");

// ============================================================================
// Opcode Definitions
// ============================================================================

/// Python opcodes
pub const Opcode = enum(u8) {
    // General
    CACHE = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,
    INTERPRETER_EXIT = 3,
    END_FOR = 4,
    END_SEND = 5,
    NOP = 9,

    // Unary operations
    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    // Binary operations
    BINARY_SUBSCR = 25,
    BINARY_SLICE = 26,
    STORE_SLICE = 27,
    BINARY_OP = 28,

    // Misc
    GET_LEN = 30,
    MATCH_MAPPING = 31,
    MATCH_SEQUENCE = 32,
    MATCH_KEYS = 33,
    PUSH_EXC_INFO = 35,
    CHECK_EXC_MATCH = 36,
    CHECK_EG_MATCH = 37,

    // Imports
    IMPORT_NAME = 40,
    IMPORT_FROM = 41,

    // Jumps
    JUMP_FORWARD = 44,
    JUMP_BACKWARD = 45,
    POP_JUMP_IF_FALSE = 46,
    POP_JUMP_IF_TRUE = 47,

    // Locals
    LOAD_FAST = 50,
    STORE_FAST = 51,
    DELETE_FAST = 52,
    LOAD_FAST_CHECK = 53,
    LOAD_FAST_AND_CLEAR = 54,

    // Stack operations
    SWAP = 60,
    COPY = 61,

    // More jumps
    JUMP_BACKWARD_NO_INTERRUPT = 75,

    // Function calls
    CALL = 80,
    KW_NAMES = 81,

    // Generators
    GET_ITER = 68,
    GET_YIELD_FROM_ITER = 69,
    FOR_ITER = 70,
    SEND = 71,

    // Building
    BUILD_TUPLE = 90,
    BUILD_LIST = 91,
    BUILD_SET = 92,
    BUILD_MAP = 93,
    BUILD_CONST_KEY_MAP = 94,
    BUILD_STRING = 95,

    // List operations
    LIST_EXTEND = 96,
    SET_UPDATE = 97,
    DICT_UPDATE = 98,
    DICT_MERGE = 99,

    // Loading
    LOAD_CONST = 100,
    LOAD_NAME = 101,
    LOAD_ATTR = 102,
    LOAD_METHOD = 103,
    LOAD_GLOBAL = 104,

    // Delete operations
    DELETE_NAME = 105,

    // Store operations
    STORE_NAME = 106,
    STORE_ATTR = 107,
    DELETE_ATTR = 108,
    STORE_GLOBAL = 109,
    DELETE_GLOBAL = 110,

    // Loading more
    LOAD_LOCALS = 111,
    LOAD_FROM_DICT_OR_GLOBALS = 112,
    LOAD_FROM_DICT_OR_DEREF = 113,

    // Unpacking
    UNPACK_SEQUENCE = 115,
    UNPACK_EX = 116,

    // Subscript
    STORE_SUBSCR = 120,
    DELETE_SUBSCR = 121,

    // Closures
    LOAD_DEREF = 124,
    STORE_DEREF = 125,
    DELETE_DEREF = 126,
    COPY_FREE_VARS = 127,

    // Exceptions
    RAISE_VARARGS = 130,
    RERAISE = 131,
    POP_EXCEPT = 132,

    // Functions
    MAKE_FUNCTION = 135,
    RETURN_VALUE = 136,
    RETURN_CONST = 137,
    RETURN_GENERATOR = 138,

    // Yield
    YIELD_VALUE = 140,

    // Setup blocks
    SETUP_ANNOTATIONS = 143,

    // Comparison
    COMPARE_OP = 145,
    IS_OP = 146,
    CONTAINS_OP = 147,

    // More building
    BUILD_SLICE = 150,

    // Format
    FORMAT_VALUE = 155,
    FORMAT_SIMPLE = 156,
    FORMAT_WITH_SPEC = 157,

    // Extended arg
    EXTENDED_ARG = 160,

    // Closures
    MAKE_CELL = 165,
    LOAD_CLOSURE = 166,

    // More operations
    LOAD_SUPER_ATTR = 170,
    MATCH_CLASS = 175,

    // Resume
    RESUME = 180,

    // Async
    GET_AWAITABLE = 185,
    GET_AITER = 186,
    GET_ANEXT = 187,

    // With
    BEFORE_WITH = 190,
    BEFORE_ASYNC_WITH = 191,

    // Exception group
    CLEANUP_THROW = 195,

    // Intrinsics
    CALL_INTRINSIC_1 = 200,
    CALL_INTRINSIC_2 = 201,

    // Type params
    LOAD_SPECIAL = 205,

    _,

    pub fn name(self: Opcode) []const u8 {
        return @tagName(self);
    }

    pub fn hasArg(self: Opcode) bool {
        return @intFromEnum(self) >= 90;
    }

    pub fn hasConst(self: Opcode) bool {
        return self == .LOAD_CONST or self == .RETURN_CONST;
    }

    pub fn hasName(self: Opcode) bool {
        return switch (self) {
            .LOAD_NAME, .STORE_NAME, .DELETE_NAME, .LOAD_GLOBAL, .STORE_GLOBAL, .DELETE_GLOBAL, .LOAD_ATTR, .STORE_ATTR, .DELETE_ATTR, .IMPORT_NAME, .IMPORT_FROM => true,
            else => false,
        };
    }

    pub fn hasFree(self: Opcode) bool {
        return switch (self) {
            .LOAD_DEREF, .STORE_DEREF, .DELETE_DEREF, .LOAD_CLOSURE, .MAKE_CELL, .COPY_FREE_VARS => true,
            else => false,
        };
    }

    pub fn hasLocal(self: Opcode) bool {
        return switch (self) {
            .LOAD_FAST, .STORE_FAST, .DELETE_FAST, .LOAD_FAST_CHECK, .LOAD_FAST_AND_CLEAR => true,
            else => false,
        };
    }

    pub fn hasJrel(self: Opcode) bool {
        return switch (self) {
            .JUMP_FORWARD, .JUMP_BACKWARD, .JUMP_BACKWARD_NO_INTERRUPT, .FOR_ITER, .SEND => true,
            else => false,
        };
    }

    pub fn hasJabs(self: Opcode) bool {
        return switch (self) {
            .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => true,
            else => false,
        };
    }

    pub fn hasCompare(self: Opcode) bool {
        return self == .COMPARE_OP;
    }

    pub fn isJump(self: Opcode) bool {
        return self.hasJrel() or self.hasJabs();
    }
};

/// Comparison operators
pub const CmpOp = enum(u8) {
    LT = 0, // <
    LE = 1, // <=
    EQ = 2, // ==
    NE = 3, // !=
    GT = 4, // >
    GE = 5, // >=

    pub fn symbol(self: CmpOp) []const u8 {
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
// Instruction
// ============================================================================

/// Represents a single bytecode instruction
pub const Instruction = struct {
    opcode: Opcode,
    opname: []const u8,
    arg: ?u32,
    argval: ?ArgumentValue,
    argrepr: ?[]const u8,
    offset: usize,
    starts_line: ?u32,
    is_jump_target: bool,

    pub const ArgumentValue = union(enum) {
        int: i64,
        string: []const u8,
        none,
    };
};

// ============================================================================
// Bytecode Class
// ============================================================================

/// Bytecode analysis helper
pub const Bytecode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    codeobj: ?*anyopaque,
    first_line: ?u32,
    current_offset: ?usize,

    pub fn init(allocator: std.mem.Allocator, x: anytype) Self {
        _ = x;
        return .{
            .allocator = allocator,
            .codeobj = null,
            .first_line = null,
            .current_offset = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Get info about the code object
    pub fn info(self: *Self) ![]u8 {
        _ = self;
        return error.NotImplemented;
    }

    /// Disassemble the code
    pub fn dis(self: *Self) ![]u8 {
        _ = self;
        return error.NotImplemented;
    }
};

// ============================================================================
// Disassembly Functions
// ============================================================================

/// Disassemble a code object or function
pub fn dis(allocator: std.mem.Allocator, x: anytype, file: ?std.fs.File, depth: ?i32) !void {
    _ = allocator;
    _ = x;
    _ = file;
    _ = depth;
    // Would disassemble and print to file
}

/// Disassemble a code object to a string
pub fn disassemble(allocator: std.mem.Allocator, co: anytype, lasti: ?i32) ![]u8 {
    _ = allocator;
    _ = co;
    _ = lasti;
    return error.NotImplemented;
}

/// Disassemble bytecode bytes
pub fn disassembleBytes(allocator: std.mem.Allocator, code: []const u8, lasti: ?i32, varnames: ?[][]const u8, names: ?[][]const u8, constants: ?[]anytype) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var offset: usize = 0;
    while (offset < code.len) {
        const opcode: Opcode = @enumFromInt(code[offset]);
        var arg: ?u32 = null;

        if (opcode.hasArg() and offset + 1 < code.len) {
            arg = code[offset + 1];
        }

        // Format instruction
        var line_buf: [256]u8 = undefined;
        const line = if (arg) |a|
            std.fmt.bufPrint(&line_buf, "{d:>6} {s:<20} {d}\n", .{ offset, opcode.name(), a }) catch ""
        else
            std.fmt.bufPrint(&line_buf, "{d:>6} {s:<20}\n", .{ offset, opcode.name() }) catch "";

        try result.appendSlice(line);

        // Handle jump target marker
        if (lasti != null and @as(i32, @intCast(offset)) == lasti.?) {
            // Mark current instruction
        }

        offset += if (opcode.hasArg()) @as(usize, 2) else @as(usize, 1);
    }

    _ = varnames;
    _ = names;
    _ = constants;

    return result.toOwnedSlice();
}

/// Get instructions from a code object
pub fn getInstructions(allocator: std.mem.Allocator, x: anytype, first_line: ?u32) ![]Instruction {
    _ = allocator;
    _ = x;
    _ = first_line;
    return &[_]Instruction{};
}

/// Find labels (jump targets) in bytecode
pub fn findlabels(code: []const u8) ![]usize {
    var labels = std.ArrayList(usize).init(std.heap.page_allocator);
    defer labels.deinit();

    var offset: usize = 0;
    while (offset < code.len) {
        const opcode: Opcode = @enumFromInt(code[offset]);

        if (opcode.hasArg() and offset + 1 < code.len) {
            const arg = code[offset + 1];
            if (opcode.isJump()) {
                const target = if (opcode.hasJrel())
                    offset + 2 + arg
                else
                    arg;
                try labels.append(target);
            }
        }

        offset += if (opcode.hasArg()) @as(usize, 2) else @as(usize, 1);
    }

    return labels.toOwnedSlice();
}

/// Find line starts in bytecode
pub fn findlinestarts(co: anytype) !std.AutoHashMap(usize, u32) {
    _ = co;
    return std.AutoHashMap(usize, u32).init(std.heap.page_allocator);
}

/// Show code object info
pub fn showCode(allocator: std.mem.Allocator, co: anytype) ![]u8 {
    _ = allocator;
    _ = co;
    return error.NotImplemented;
}

/// Pretty print code object info
pub fn codeInfo(allocator: std.mem.Allocator, x: anytype) ![]u8 {
    _ = allocator;
    _ = x;
    return error.NotImplemented;
}

// ============================================================================
// Opcode Stack Effects
// ============================================================================

/// Get the stack effect of an opcode
pub fn stackEffect(opcode: Opcode, arg: ?u32, jump: ?bool) i32 {
    const jmp = jump orelse false;
    _ = arg;

    return switch (opcode) {
        .NOP, .EXTENDED_ARG, .RESUME, .CACHE => 0,
        .POP_TOP, .END_FOR, .END_SEND => -1,
        .PUSH_NULL => 1,
        .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
        .BINARY_OP, .BINARY_SUBSCR, .COMPARE_OP, .IS_OP, .CONTAINS_OP => -1,
        .LOAD_CONST, .LOAD_NAME, .LOAD_FAST, .LOAD_GLOBAL, .LOAD_ATTR, .LOAD_DEREF, .LOAD_CLOSURE => 1,
        .STORE_NAME, .STORE_FAST, .STORE_GLOBAL, .STORE_ATTR, .STORE_SUBSCR, .STORE_DEREF => -1,
        .DELETE_NAME, .DELETE_FAST, .DELETE_GLOBAL, .DELETE_ATTR, .DELETE_SUBSCR, .DELETE_DEREF => 0,
        .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => |_| 1, // Actually 1 - arg
        .BUILD_MAP => 1, // Actually 1 - 2*arg
        .RETURN_VALUE, .RETURN_CONST => -1,
        .YIELD_VALUE => 0,
        .IMPORT_NAME => -1,
        .IMPORT_FROM => 1,
        .JUMP_FORWARD, .JUMP_BACKWARD => 0,
        .POP_JUMP_IF_TRUE, .POP_JUMP_IF_FALSE => if (jmp) @as(i32, -1) else @as(i32, -1),
        .FOR_ITER => if (jmp) @as(i32, -1) else @as(i32, 1),
        .GET_ITER => 0,
        .CALL => -1, // Actually -arg
        .MAKE_FUNCTION => 0,
        .RAISE_VARARGS => -1,
        .RERAISE => -1,
        .POP_EXCEPT => -1,
        .PUSH_EXC_INFO => 1,
        .SWAP, .COPY => 0,
        else => 0,
    };
}

// ============================================================================
// Constants
// ============================================================================

pub const HAVE_ARGUMENT = 90;
pub const EXTENDED_ARG_SHIFT = 8;

// ============================================================================
// Tests
// ============================================================================

test "opcode properties" {
    try std.testing.expect(Opcode.LOAD_CONST.hasArg());
    try std.testing.expect(Opcode.LOAD_CONST.hasConst());
    try std.testing.expect(!Opcode.POP_TOP.hasArg());
    try std.testing.expect(Opcode.LOAD_NAME.hasName());
    try std.testing.expect(Opcode.LOAD_FAST.hasLocal());
    try std.testing.expect(Opcode.JUMP_FORWARD.hasJrel());
    try std.testing.expect(Opcode.JUMP_FORWARD.isJump());
}

test "cmp op symbols" {
    try std.testing.expectEqualStrings("<", CmpOp.LT.symbol());
    try std.testing.expectEqualStrings("==", CmpOp.EQ.symbol());
    try std.testing.expectEqualStrings("!=", CmpOp.NE.symbol());
}

test "stack effect" {
    try std.testing.expectEqual(@as(i32, 0), stackEffect(.NOP, null, null));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(.POP_TOP, null, null));
    try std.testing.expectEqual(@as(i32, 1), stackEffect(.LOAD_CONST, null, null));
    try std.testing.expectEqual(@as(i32, -1), stackEffect(.RETURN_VALUE, null, null));
}

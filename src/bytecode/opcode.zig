/// Unified bytecode opcodes for eval()/exec()
/// Works on all targets: native, browser WASM, WasmEdge WASI
///
/// Design principles:
/// 1. Stack-based (simple, small code)
/// 2. Compact encoding (1-4 bytes per instruction)
/// 3. Full Python semantics (not just expressions)
/// 4. Dead code eliminated when unused
const std = @import("std");

/// Bytecode version for compatibility checking
pub const VERSION: u32 = 1;

/// Maximum stack depth (configurable per-target via comptime)
pub const MAX_STACK_DEPTH: usize = 1024;

/// OpCode enum - all Python operations
/// Based on CPython's opcodes but simplified and unified
pub const OpCode = enum(u8) {
    // ========== Stack Operations ==========
    /// Pop top of stack
    POP_TOP = 0x00,
    /// Rotate top 2 items
    ROT_TWO = 0x01,
    /// Rotate top 3 items
    ROT_THREE = 0x02,
    /// Duplicate top of stack
    DUP_TOP = 0x03,
    /// No operation
    NOP = 0x04,

    // ========== Unary Operations ==========
    /// TOS = +TOS
    UNARY_POSITIVE = 0x10,
    /// TOS = -TOS
    UNARY_NEGATIVE = 0x11,
    /// TOS = not TOS
    UNARY_NOT = 0x12,
    /// TOS = ~TOS
    UNARY_INVERT = 0x13,

    // ========== Binary Operations ==========
    /// TOS = TOS1 + TOS
    BINARY_ADD = 0x20,
    /// TOS = TOS1 - TOS
    BINARY_SUBTRACT = 0x21,
    /// TOS = TOS1 * TOS
    BINARY_MULTIPLY = 0x22,
    /// TOS = TOS1 / TOS (true division)
    BINARY_TRUE_DIVIDE = 0x23,
    /// TOS = TOS1 // TOS (floor division)
    BINARY_FLOOR_DIVIDE = 0x24,
    /// TOS = TOS1 % TOS
    BINARY_MODULO = 0x25,
    /// TOS = TOS1 ** TOS
    BINARY_POWER = 0x26,
    /// TOS = TOS1 @ TOS (matrix multiply)
    BINARY_MATRIX_MULTIPLY = 0x27,
    /// TOS = TOS1 << TOS
    BINARY_LSHIFT = 0x28,
    /// TOS = TOS1 >> TOS
    BINARY_RSHIFT = 0x29,
    /// TOS = TOS1 & TOS
    BINARY_AND = 0x2A,
    /// TOS = TOS1 | TOS
    BINARY_OR = 0x2B,
    /// TOS = TOS1 ^ TOS
    BINARY_XOR = 0x2C,

    // ========== In-Place Operations ==========
    INPLACE_ADD = 0x30,
    INPLACE_SUBTRACT = 0x31,
    INPLACE_MULTIPLY = 0x32,
    INPLACE_TRUE_DIVIDE = 0x33,
    INPLACE_FLOOR_DIVIDE = 0x34,
    INPLACE_MODULO = 0x35,
    INPLACE_POWER = 0x36,
    INPLACE_LSHIFT = 0x38,
    INPLACE_RSHIFT = 0x39,
    INPLACE_AND = 0x3A,
    INPLACE_OR = 0x3B,
    INPLACE_XOR = 0x3C,

    // ========== Comparison Operations ==========
    /// TOS = TOS1 < TOS
    COMPARE_LT = 0x40,
    /// TOS = TOS1 <= TOS
    COMPARE_LE = 0x41,
    /// TOS = TOS1 == TOS
    COMPARE_EQ = 0x42,
    /// TOS = TOS1 != TOS
    COMPARE_NE = 0x43,
    /// TOS = TOS1 > TOS
    COMPARE_GT = 0x44,
    /// TOS = TOS1 >= TOS
    COMPARE_GE = 0x45,
    /// TOS = TOS1 in TOS
    COMPARE_IN = 0x46,
    /// TOS = TOS1 not in TOS
    COMPARE_NOT_IN = 0x47,
    /// TOS = TOS1 is TOS
    COMPARE_IS = 0x48,
    /// TOS = TOS1 is not TOS
    COMPARE_IS_NOT = 0x49,

    // ========== Load/Store Operations ==========
    /// Push constant[arg] onto stack
    LOAD_CONST = 0x50,
    /// Push names[arg] value onto stack
    LOAD_NAME = 0x51,
    /// Push fast locals[arg] onto stack
    LOAD_FAST = 0x52,
    /// Push globals[arg] onto stack
    LOAD_GLOBAL = 0x53,
    /// Push closure[arg] onto stack
    LOAD_DEREF = 0x54,
    /// Store TOS into names[arg]
    STORE_NAME = 0x55,
    /// Store TOS into fast locals[arg]
    STORE_FAST = 0x56,
    /// Store TOS into globals[arg]
    STORE_GLOBAL = 0x57,
    /// Store TOS into closure[arg]
    STORE_DEREF = 0x58,
    /// Delete names[arg]
    DELETE_NAME = 0x59,
    /// Delete fast locals[arg]
    DELETE_FAST = 0x5A,
    /// Delete globals[arg]
    DELETE_GLOBAL = 0x5B,

    // ========== Attribute Operations ==========
    /// TOS = TOS.names[arg]
    LOAD_ATTR = 0x60,
    /// TOS.names[arg] = TOS1; pop 2
    STORE_ATTR = 0x61,
    /// del TOS.names[arg]
    DELETE_ATTR = 0x62,

    // ========== Subscript Operations ==========
    /// TOS = TOS1[TOS]
    BINARY_SUBSCR = 0x70,
    /// TOS1[TOS] = TOS2; pop 3
    STORE_SUBSCR = 0x71,
    /// del TOS1[TOS]; pop 2
    DELETE_SUBSCR = 0x72,

    // ========== Control Flow ==========
    /// Jump to arg
    JUMP_ABSOLUTE = 0x80,
    /// Jump forward by arg
    JUMP_FORWARD = 0x81,
    /// Jump to arg if TOS is false (pop TOS)
    POP_JUMP_IF_FALSE = 0x82,
    /// Jump to arg if TOS is true (pop TOS)
    POP_JUMP_IF_TRUE = 0x83,
    /// Jump to arg if TOS is false (keep TOS)
    JUMP_IF_FALSE_OR_POP = 0x84,
    /// Jump to arg if TOS is true (keep TOS)
    JUMP_IF_TRUE_OR_POP = 0x85,

    // ========== Loop Operations ==========
    /// Push iterator of TOS
    GET_ITER = 0x90,
    /// TOS = next(TOS1); jump to arg on StopIteration
    FOR_ITER = 0x91,

    // ========== Function Operations ==========
    /// Call function with arg positional args
    CALL_FUNCTION = 0xA0,
    /// Call function with arg positional + keyword args
    CALL_FUNCTION_KW = 0xA1,
    /// Call function with *args and **kwargs
    CALL_FUNCTION_EX = 0xA2,
    /// Return TOS from function
    RETURN_VALUE = 0xA3,
    /// Yield TOS from generator
    YIELD_VALUE = 0xA4,
    /// Yield from TOS iterator
    YIELD_FROM = 0xA5,

    // ========== Build Operations ==========
    /// Build tuple from arg items
    BUILD_TUPLE = 0xB0,
    /// Build list from arg items
    BUILD_LIST = 0xB1,
    /// Build set from arg items
    BUILD_SET = 0xB2,
    /// Build dict from arg pairs
    BUILD_MAP = 0xB3,
    /// Build string from arg items
    BUILD_STRING = 0xB4,
    /// Build slice (arg: 2 or 3 for step)
    BUILD_SLICE = 0xB5,
    /// Unpack sequence into arg items
    UNPACK_SEQUENCE = 0xB6,
    /// Unpack with star (*items)
    UNPACK_EX = 0xB7,

    // ========== Collection Operations ==========
    /// Append TOS to list TOS1
    LIST_APPEND = 0xC0,
    /// Add TOS to set TOS1
    SET_ADD = 0xC1,
    /// TOS2[TOS1] = TOS in map building
    MAP_ADD = 0xC2,
    /// Extend list TOS1 with iterable TOS
    LIST_EXTEND = 0xC3,
    /// Update set TOS1 with iterable TOS
    SET_UPDATE = 0xC4,
    /// Update dict TOS1 with mapping TOS
    DICT_UPDATE = 0xC5,
    /// Merge dict TOS1 with mapping TOS
    DICT_MERGE = 0xC6,

    // ========== Class Operations ==========
    /// Build class from name, bases, dict
    BUILD_CLASS = 0xD0,
    /// Load method for TOS object
    LOAD_METHOD = 0xD1,
    /// Call method with arg args
    CALL_METHOD = 0xD2,

    // ========== Import Operations ==========
    /// Import module names[arg]
    IMPORT_NAME = 0xE0,
    /// Import names[arg] from TOS module
    IMPORT_FROM = 0xE1,
    /// Import * from TOS module
    IMPORT_STAR = 0xE2,

    // ========== Exception Operations ==========
    /// Setup try block, jump to arg on exception
    SETUP_EXCEPT = 0xF0,
    /// Setup finally block
    SETUP_FINALLY = 0xF1,
    /// Pop exception block
    POP_EXCEPT = 0xF2,
    /// Raise exception TOS
    RAISE_VARARGS = 0xF3,
    /// Re-raise current exception
    RERAISE = 0xF4,
    /// Setup with block
    SETUP_WITH = 0xF5,
    /// End with block
    WITH_CLEANUP_START = 0xF6,
    WITH_CLEANUP_FINISH = 0xF7,

    // ========== Async Operations ==========
    /// Get awaitable from TOS
    GET_AWAITABLE = 0xF8,
    /// Get async iterator from TOS
    GET_AITER = 0xF9,
    /// Get next from async iterator
    GET_ANEXT = 0xFA,
    /// End async for loop
    END_ASYNC_FOR = 0xFB,

    // ========== Format Operations ==========
    /// Format TOS with format spec
    FORMAT_VALUE = 0xFC,

    // ========== Extended ==========
    /// Extended arg (next instruction uses arg << 8 | next_arg)
    EXTENDED_ARG = 0xFE,
    /// Halt execution
    HALT = 0xFF,

    /// Check if opcode has an argument
    pub fn hasArg(self: OpCode) bool {
        return @intFromEnum(self) >= 0x50;
    }

    /// Get stack effect (positive = push, negative = pop)
    pub fn stackEffect(self: OpCode, arg: u24) i32 {
        return switch (self) {
            .POP_TOP => -1,
            .ROT_TWO, .ROT_THREE => 0,
            .DUP_TOP => 1,
            .NOP => 0,
            .UNARY_POSITIVE, .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
            .BINARY_ADD, .BINARY_SUBTRACT, .BINARY_MULTIPLY, .BINARY_TRUE_DIVIDE, .BINARY_FLOOR_DIVIDE, .BINARY_MODULO, .BINARY_POWER, .BINARY_MATRIX_MULTIPLY, .BINARY_LSHIFT, .BINARY_RSHIFT, .BINARY_AND, .BINARY_OR, .BINARY_XOR => -1,
            .INPLACE_ADD, .INPLACE_SUBTRACT, .INPLACE_MULTIPLY, .INPLACE_TRUE_DIVIDE, .INPLACE_FLOOR_DIVIDE, .INPLACE_MODULO, .INPLACE_POWER, .INPLACE_LSHIFT, .INPLACE_RSHIFT, .INPLACE_AND, .INPLACE_OR, .INPLACE_XOR => -1,
            .COMPARE_LT, .COMPARE_LE, .COMPARE_EQ, .COMPARE_NE, .COMPARE_GT, .COMPARE_GE, .COMPARE_IN, .COMPARE_NOT_IN, .COMPARE_IS, .COMPARE_IS_NOT => -1,
            .LOAD_CONST, .LOAD_NAME, .LOAD_FAST, .LOAD_GLOBAL, .LOAD_DEREF => 1,
            .STORE_NAME, .STORE_FAST, .STORE_GLOBAL, .STORE_DEREF => -1,
            .DELETE_NAME, .DELETE_FAST, .DELETE_GLOBAL => 0,
            .LOAD_ATTR => 0,
            .STORE_ATTR => -2,
            .DELETE_ATTR => -1,
            .BINARY_SUBSCR => -1,
            .STORE_SUBSCR => -3,
            .DELETE_SUBSCR => -2,
            .JUMP_ABSOLUTE, .JUMP_FORWARD => 0,
            .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => -1,
            .JUMP_IF_FALSE_OR_POP, .JUMP_IF_TRUE_OR_POP => 0, // depends on branch
            .GET_ITER => 0,
            .FOR_ITER => 1, // or 0 if exhausted
            .CALL_FUNCTION => -@as(i32, @intCast(arg)),
            .CALL_FUNCTION_KW => -@as(i32, @intCast(arg)) - 1,
            .CALL_FUNCTION_EX => -1, // complex
            .RETURN_VALUE => -1,
            .YIELD_VALUE => 0,
            .YIELD_FROM => -1,
            .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => 1 - @as(i32, @intCast(arg)),
            .BUILD_MAP => 1 - 2 * @as(i32, @intCast(arg)),
            .BUILD_STRING => 1 - @as(i32, @intCast(arg)),
            .BUILD_SLICE => if (arg == 2) -1 else -2,
            .UNPACK_SEQUENCE => @as(i32, @intCast(arg)) - 1,
            .UNPACK_EX => @as(i32, @intCast(arg & 0xFF)) + @as(i32, @intCast(arg >> 8)),
            .LIST_APPEND, .SET_ADD, .MAP_ADD => -1,
            .LIST_EXTEND, .SET_UPDATE, .DICT_UPDATE, .DICT_MERGE => -1,
            .BUILD_CLASS => -2,
            .LOAD_METHOD => 1,
            .CALL_METHOD => -@as(i32, @intCast(arg)) - 1,
            .IMPORT_NAME => -1,
            .IMPORT_FROM => 1,
            .IMPORT_STAR => -1,
            .SETUP_EXCEPT, .SETUP_FINALLY, .SETUP_WITH => 0,
            .POP_EXCEPT => -1,
            .RAISE_VARARGS => -@as(i32, @intCast(arg)),
            .RERAISE => 0,
            .WITH_CLEANUP_START, .WITH_CLEANUP_FINISH => 0,
            .GET_AWAITABLE, .GET_AITER, .GET_ANEXT => 0,
            .END_ASYNC_FOR => -1,
            .FORMAT_VALUE => if (arg & 0x04 != 0) -1 else 0,
            .EXTENDED_ARG => 0,
            .HALT => 0,
        };
    }
};

/// Single bytecode instruction
pub const Instruction = packed struct {
    opcode: OpCode,
    arg: u24,

    pub fn init(opcode: OpCode, arg: u24) Instruction {
        return .{ .opcode = opcode, .arg = arg };
    }

    pub fn simple(opcode: OpCode) Instruction {
        return .{ .opcode = opcode, .arg = 0 };
    }
};

/// Source location for error messages
pub const SourceLoc = struct {
    /// Python source line number
    line: u32,
    /// Column offset (optional)
    column: u16 = 0,
    /// Instruction offset this applies to
    offset: u32,
};

/// Constant value in the constant pool
pub const Value = union(enum) {
    none,
    bool: bool,
    int: i64,
    bigint: []const u8, // serialized BigInt
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,
    tuple: []const Value,
    frozenset: []const Value,
    code: *const Program, // nested code object
};

/// Compiled bytecode program
pub const Program = struct {
    /// Bytecode instructions
    instructions: []const Instruction,
    /// Constant pool
    constants: []const Value,
    /// Local variable names
    varnames: []const []const u8,
    /// Global/free variable names
    names: []const []const u8,
    /// Cell variable names (for closures)
    cellvars: []const []const u8,
    /// Free variable names (from enclosing scope)
    freevars: []const []const u8,
    /// Source locations for error messages
    source_map: []const SourceLoc,
    /// Source filename
    filename: []const u8,
    /// Function/module name
    name: []const u8,
    /// First line number in source
    firstlineno: u32,
    /// Number of arguments (for functions)
    argcount: u32,
    /// Number of positional-only args
    posonlyargcount: u32,
    /// Number of keyword-only args
    kwonlyargcount: u32,
    /// Stack size needed
    stacksize: u32,
    /// Flags (generator, async, etc.)
    flags: Flags,

    pub const Flags = packed struct {
        is_generator: bool = false,
        is_coroutine: bool = false,
        is_async_generator: bool = false,
        has_varargs: bool = false,
        has_kwargs: bool = false,
        is_nested: bool = false,
        _padding: u2 = 0,
    };

    /// Clean up program resources
    pub fn deinit(self: *Program, allocator: std.mem.Allocator) void {
        allocator.free(self.instructions);
        for (self.constants) |c| {
            switch (c) {
                .string, .bytes, .bigint => |s| allocator.free(s),
                .tuple, .frozenset => |items| {
                    for (items) |item| {
                        switch (item) {
                            .string, .bytes, .bigint => |s| allocator.free(s),
                            else => {},
                        }
                    }
                    allocator.free(items);
                },
                .code => |code| {
                    var mutable_code = @constCast(code);
                    mutable_code.deinit(allocator);
                    allocator.destroy(mutable_code);
                },
                else => {},
            }
        }
        allocator.free(self.constants);
        for (self.varnames) |n| allocator.free(n);
        allocator.free(self.varnames);
        for (self.names) |n| allocator.free(n);
        allocator.free(self.names);
        for (self.cellvars) |n| allocator.free(n);
        allocator.free(self.cellvars);
        for (self.freevars) |n| allocator.free(n);
        allocator.free(self.freevars);
        allocator.free(self.source_map);
        allocator.free(self.filename);
        allocator.free(self.name);
    }
};

/// Serialize program to bytes (for WASM transfer)
pub fn serialize(program: *const Program, allocator: std.mem.Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    const w = buf.writer();

    // Version header
    try w.writeInt(u32, VERSION, .little);

    // Instructions
    try w.writeInt(u32, @intCast(program.instructions.len), .little);
    for (program.instructions) |inst| {
        try w.writeInt(u8, @intFromEnum(inst.opcode), .little);
        try w.writeInt(u24, inst.arg, .little);
    }

    // Constants
    try w.writeInt(u32, @intCast(program.constants.len), .little);
    for (program.constants) |constant| {
        try serializeValue(constant, w);
    }

    // Varnames
    try w.writeInt(u32, @intCast(program.varnames.len), .little);
    for (program.varnames) |name| {
        try w.writeInt(u32, @intCast(name.len), .little);
        try w.writeAll(name);
    }

    // Names
    try w.writeInt(u32, @intCast(program.names.len), .little);
    for (program.names) |name| {
        try w.writeInt(u32, @intCast(name.len), .little);
        try w.writeAll(name);
    }

    // Source map
    try w.writeInt(u32, @intCast(program.source_map.len), .little);
    for (program.source_map) |loc| {
        try w.writeInt(u32, loc.line, .little);
        try w.writeInt(u16, loc.column, .little);
        try w.writeInt(u32, loc.offset, .little);
    }

    // Filename
    try w.writeInt(u32, @intCast(program.filename.len), .little);
    try w.writeAll(program.filename);

    // Name
    try w.writeInt(u32, @intCast(program.name.len), .little);
    try w.writeAll(program.name);

    // Metadata
    try w.writeInt(u32, program.firstlineno, .little);
    try w.writeInt(u32, program.argcount, .little);
    try w.writeInt(u32, program.posonlyargcount, .little);
    try w.writeInt(u32, program.kwonlyargcount, .little);
    try w.writeInt(u32, program.stacksize, .little);

    return buf.toOwnedSlice(allocator);
}

fn serializeValue(value: Value, w: anytype) !void {
    switch (value) {
        .none => try w.writeByte(0),
        .bool => |b| {
            try w.writeByte(1);
            try w.writeByte(if (b) 1 else 0);
        },
        .int => |i| {
            try w.writeByte(2);
            try w.writeInt(i64, i, .little);
        },
        .float => |f| {
            try w.writeByte(3);
            try w.writeInt(u64, @bitCast(f), .little);
        },
        .string => |s| {
            try w.writeByte(4);
            try w.writeInt(u32, @intCast(s.len), .little);
            try w.writeAll(s);
        },
        .bytes => |b| {
            try w.writeByte(5);
            try w.writeInt(u32, @intCast(b.len), .little);
            try w.writeAll(b);
        },
        .tuple => |t| {
            try w.writeByte(6);
            try w.writeInt(u32, @intCast(t.len), .little);
            for (t) |elem| {
                try serializeValue(elem, w);
            }
        },
        .code => |_| {
            // Nested code objects - write placeholder for now
            try w.writeByte(7);
        },
        else => try w.writeByte(0xFF), // Unknown type marker
    }
}

/// Deserialize program from bytes
pub fn deserialize(data: []const u8, allocator: std.mem.Allocator) !*Program {
    var stream = std.io.fixedBufferStream(data);
    const r = stream.reader();

    // Version header
    const version = try r.readInt(u32, .little);
    if (version != VERSION) return error.VersionMismatch;

    // Instructions
    const instr_count = try r.readInt(u32, .little);
    const instructions = try allocator.alloc(Instruction, instr_count);
    for (instructions) |*inst| {
        inst.opcode = @enumFromInt(try r.readByte());
        inst.arg = try r.readInt(u24, .little);
    }

    // Constants
    const const_count = try r.readInt(u32, .little);
    const constants = try allocator.alloc(Value, const_count);
    for (constants) |*constant| {
        constant.* = try deserializeValue(r, allocator);
    }

    // Varnames
    const varnames_count = try r.readInt(u32, .little);
    const varnames = try allocator.alloc([]const u8, varnames_count);
    for (varnames) |*name| {
        const len = try r.readInt(u32, .little);
        const buf = try allocator.alloc(u8, len);
        _ = try r.readAll(buf);
        name.* = buf;
    }

    // Names
    const names_count = try r.readInt(u32, .little);
    const names = try allocator.alloc([]const u8, names_count);
    for (names) |*name| {
        const len = try r.readInt(u32, .little);
        const buf = try allocator.alloc(u8, len);
        _ = try r.readAll(buf);
        name.* = buf;
    }

    // Source map
    const source_map_count = try r.readInt(u32, .little);
    const source_map = try allocator.alloc(SourceLoc, source_map_count);
    for (source_map) |*loc| {
        loc.line = try r.readInt(u32, .little);
        loc.column = try r.readInt(u16, .little);
        loc.offset = try r.readInt(u32, .little);
    }

    // Filename
    const filename_len = try r.readInt(u32, .little);
    const filename = try allocator.alloc(u8, filename_len);
    _ = try r.readAll(filename);

    // Name
    const name_len = try r.readInt(u32, .little);
    const name = try allocator.alloc(u8, name_len);
    _ = try r.readAll(name);

    // Metadata
    const firstlineno = try r.readInt(u32, .little);
    const argcount = try r.readInt(u32, .little);
    const posonlyargcount = try r.readInt(u32, .little);
    const kwonlyargcount = try r.readInt(u32, .little);
    const stacksize = try r.readInt(u32, .little);

    const program = try allocator.create(Program);
    program.* = .{
        .instructions = instructions,
        .constants = constants,
        .varnames = varnames,
        .names = names,
        .cellvars = &.{},
        .freevars = &.{},
        .source_map = source_map,
        .filename = filename,
        .name = name,
        .firstlineno = firstlineno,
        .argcount = argcount,
        .posonlyargcount = posonlyargcount,
        .kwonlyargcount = kwonlyargcount,
        .stacksize = stacksize,
        .flags = .{},
    };

    return program;
}

fn deserializeValue(r: anytype, allocator: std.mem.Allocator) !Value {
    const tag = try r.readByte();
    return switch (tag) {
        0 => .none,
        1 => .{ .bool = try r.readByte() != 0 },
        2 => .{ .int = try r.readInt(i64, .little) },
        3 => .{ .float = @bitCast(try r.readInt(u64, .little)) },
        4 => blk: {
            const len = try r.readInt(u32, .little);
            const buf = try allocator.alloc(u8, len);
            _ = try r.readAll(buf);
            break :blk .{ .string = buf };
        },
        5 => blk: {
            const len = try r.readInt(u32, .little);
            const buf = try allocator.alloc(u8, len);
            _ = try r.readAll(buf);
            break :blk .{ .bytes = buf };
        },
        6 => blk: {
            const count = try r.readInt(u32, .little);
            const tuple = try allocator.alloc(Value, count);
            for (tuple) |*elem| {
                elem.* = try deserializeValue(r, allocator);
            }
            break :blk .{ .tuple = tuple };
        },
        7 => .none, // Placeholder for nested code
        else => .none,
    };
}

test "opcode basics" {
    const inst = Instruction.init(.LOAD_CONST, 42);
    try std.testing.expectEqual(OpCode.LOAD_CONST, inst.opcode);
    try std.testing.expectEqual(@as(u24, 42), inst.arg);
    try std.testing.expect(OpCode.LOAD_CONST.hasArg());
    try std.testing.expect(!OpCode.POP_TOP.hasArg());
}

test "stack effects" {
    try std.testing.expectEqual(@as(i32, 1), OpCode.LOAD_CONST.stackEffect(0));
    try std.testing.expectEqual(@as(i32, -1), OpCode.BINARY_ADD.stackEffect(0));
    try std.testing.expectEqual(@as(i32, -3), OpCode.CALL_FUNCTION.stackEffect(3));
}

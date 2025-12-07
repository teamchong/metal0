/// codegen - Code Generation
/// Mirrors cpython/Python/codegen.c
///
/// The code generator transforms AST nodes into bytecode instructions.
/// It handles scope analysis, variable resolution, and instruction emission.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Code Generation Context
// ============================================================================

/// Compilation flags
pub const CompileFlags = packed struct {
    /// Optimize for speed
    optimize: bool = false,
    /// Generate code for interactive mode
    interactive: bool = false,
    /// Don't imply 'from __future__ import'
    no_future: bool = false,
    /// Use annotations as strings (PEP 563)
    annotations: bool = false,
    /// Allow top-level await
    allow_top_level_await: bool = false,
    /// In a type parameter scope
    type_params: bool = false,

    _padding: u2 = 0,
};

/// Scope type
pub const ScopeType = enum(u8) {
    module,
    class,
    function,
    lambda,
    comprehension,
    annotation,
    type_parameters,
    type_alias,
    type_variable,
};

/// Compiler unit (one per scope)
pub const CompilerUnit = struct {
    const Self = @This();

    /// Unit name
    name: []const u8,
    /// Scope type
    scope_type: ScopeType,
    /// Line number
    lineno: i32 = 1,
    /// Column offset
    col_offset: i32 = 0,
    /// Local variables
    varnames: std.ArrayList([]const u8),
    /// Cell variables (captured by nested functions)
    cellvars: std.ArrayList([]const u8),
    /// Free variables (from enclosing scope)
    freevars: std.ArrayList([]const u8),
    /// Constants pool
    consts: std.ArrayList(Constant),
    /// Names pool
    names: std.ArrayList([]const u8),
    /// Stack depth tracking
    stack_depth: i32 = 0,
    /// Maximum stack depth
    max_stack_depth: i32 = 0,
    /// Number of arguments
    argcount: u32 = 0,
    /// Number of positional-only arguments
    posonlyargcount: u32 = 0,
    /// Number of keyword-only arguments
    kwonlyargcount: u32 = 0,
    /// Flags
    flags: CodeFlags = .{},
    /// Parent unit
    parent: ?*Self = null,
    /// Allocator
    allocator: Allocator,

    /// Create new compiler unit
    pub fn init(allocator: Allocator, name: []const u8, scope_type: ScopeType) Self {
        return Self{
            .name = name,
            .scope_type = scope_type,
            .varnames = std.ArrayList([]const u8).init(allocator),
            .cellvars = std.ArrayList([]const u8).init(allocator),
            .freevars = std.ArrayList([]const u8).init(allocator),
            .consts = std.ArrayList(Constant).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free compiler unit
    pub fn deinit(self: *Self) void {
        self.varnames.deinit();
        self.cellvars.deinit();
        self.freevars.deinit();
        self.consts.deinit();
        self.names.deinit();
    }

    /// Add local variable
    pub fn addLocal(self: *Self, name: []const u8) !u32 {
        for (self.varnames.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.varnames.items.len);
        try self.varnames.append(name);
        return idx;
    }

    /// Add constant
    pub fn addConst(self: *Self, constant: Constant) !u32 {
        // Check for existing
        for (self.consts.items, 0..) |c, i| {
            if (c.eql(constant)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.consts.items.len);
        try self.consts.append(constant);
        return idx;
    }

    /// Add name
    pub fn addName(self: *Self, name: []const u8) !u32 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.names.items.len);
        try self.names.append(name);
        return idx;
    }

    /// Track stack effect
    pub fn adjustStack(self: *Self, delta: i32) void {
        self.stack_depth += delta;
        if (self.stack_depth > self.max_stack_depth) {
            self.max_stack_depth = self.stack_depth;
        }
    }
};

/// Code object flags
pub const CodeFlags = packed struct {
    optimized: bool = false,
    newlocals: bool = false,
    varargs: bool = false,
    varkeywords: bool = false,
    nested: bool = false,
    generator: bool = false,
    nofree: bool = false,
    coroutine: bool = false,
    iterable_coroutine: bool = false,
    async_generator: bool = false,

    _padding: u6 = 0,
};

// ============================================================================
// Constant Types
// ============================================================================

/// Constant value
pub const Constant = union(enum) {
    none: void,
    ellipsis: void,
    boolean: bool,
    integer: i64,
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,
    tuple: []const Constant,
    frozenset: []const Constant,
    code: *anyopaque,

    pub fn eql(self: Constant, other: Constant) bool {
        return switch (self) {
            .none => other == .none,
            .ellipsis => other == .ellipsis,
            .boolean => |b| other == .boolean and other.boolean == b,
            .integer => |i| other == .integer and other.integer == i,
            .float => |f| other == .float and other.float == f,
            .string => |s| other == .string and std.mem.eql(u8, other.string, s),
            .bytes => |b| other == .bytes and std.mem.eql(u8, other.bytes, b),
            else => false,
        };
    }
};

// ============================================================================
// Code Generator
// ============================================================================

/// Code generator state
pub const CodeGenerator = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Current compilation unit
    unit: ?*CompilerUnit = null,
    /// Unit stack
    unit_stack: std.ArrayList(*CompilerUnit),
    /// Compile flags
    flags: CompileFlags = .{},
    /// Filename
    filename: []const u8,
    /// Future features
    future: FutureFeatures = .{},
    /// Optimization level
    optimization_level: u8 = 0,
    /// Error state
    had_error: bool = false,
    /// Error message
    error_message: ?[]const u8 = null,

    /// Create code generator
    pub fn init(allocator: Allocator, filename: []const u8) Self {
        return Self{
            .allocator = allocator,
            .filename = filename,
            .unit_stack = std.ArrayList(*CompilerUnit).init(allocator),
        };
    }

    /// Free code generator
    pub fn deinit(self: *Self) void {
        while (self.unit_stack.items.len > 0) {
            const unit = self.unit_stack.pop();
            unit.deinit();
            self.allocator.destroy(unit);
        }
        self.unit_stack.deinit();
    }

    /// Enter a new scope
    pub fn enterScope(self: *Self, name: []const u8, scope_type: ScopeType) !void {
        const unit = try self.allocator.create(CompilerUnit);
        unit.* = CompilerUnit.init(self.allocator, name, scope_type);
        unit.parent = self.unit;

        if (self.unit) |current| {
            try self.unit_stack.append(current);
        }
        self.unit = unit;
    }

    /// Exit current scope
    pub fn exitScope(self: *Self) ?*CompilerUnit {
        const unit = self.unit;
        if (self.unit_stack.items.len > 0) {
            self.unit = self.unit_stack.pop();
        } else {
            self.unit = null;
        }
        return unit;
    }

    /// Record error
    pub fn setError(self: *Self, message: []const u8) void {
        self.had_error = true;
        self.error_message = message;
    }

    // ===== Compilation Methods =====

    /// Compile module
    pub fn compileModule(self: *Self, body: anytype) !*CodeObject {
        try self.enterScope("<module>", .module);

        // Emit docstring if present
        if (getDocstring(body)) |doc| {
            _ = try self.unit.?.addConst(.{ .string = doc });
        }

        // Compile body statements
        for (body) |stmt| {
            try self.compileStatement(stmt);
        }

        // Ensure return value
        try self.emit(.LOAD_CONST, try self.unit.?.addConst(.none));
        try self.emit(.RETURN_VALUE, 0);

        return self.finishCode();
    }

    /// Compile statement
    pub fn compileStatement(self: *Self, stmt: anytype) !void {
        _ = stmt;
        // Dispatch based on statement type
        // This would normally pattern match on the AST node type
    }

    /// Compile expression
    pub fn compileExpression(self: *Self, expr: anytype) !void {
        _ = expr;
        // Dispatch based on expression type
    }

    /// Emit instruction
    pub fn emit(self: *Self, opcode: Opcode, arg: u32) !void {
        if (self.unit) |unit| {
            // Track stack effect
            const effect = opcodeStackEffect(opcode, arg);
            unit.adjustStack(effect);
        }
        // Would emit to instruction stream
        _ = opcode;
        _ = arg;
    }

    /// Emit instruction with source location
    pub fn emitWithLocation(self: *Self, opcode: Opcode, arg: u32, lineno: i32, col: i32) !void {
        if (self.unit) |unit| {
            unit.lineno = lineno;
            unit.col_offset = col;
        }
        try self.emit(opcode, arg);
    }

    /// Finish code object
    fn finishCode(self: *Self) !*CodeObject {
        const unit = self.exitScope() orelse return error.NoScope;
        defer {
            unit.deinit();
            self.allocator.destroy(unit);
        }

        const code = try self.allocator.create(CodeObject);
        code.* = CodeObject{
            .name = unit.name,
            .filename = self.filename,
            .argcount = unit.argcount,
            .posonlyargcount = unit.posonlyargcount,
            .kwonlyargcount = unit.kwonlyargcount,
            .nlocals = @intCast(unit.varnames.items.len),
            .stacksize = @intCast(unit.max_stack_depth),
            .flags = unit.flags,
        };

        return code;
    }
};

// ============================================================================
// Code Object
// ============================================================================

/// Compiled code object
pub const CodeObject = struct {
    /// Function name
    name: []const u8,
    /// Filename
    filename: []const u8,
    /// First line number
    firstlineno: i32 = 1,
    /// Bytecode
    bytecode: []const u8 = &[_]u8{},
    /// Constants
    consts: []const Constant = &[_]Constant{},
    /// Names used
    names: []const []const u8 = &[_][]const u8{},
    /// Local variable names
    varnames: []const []const u8 = &[_][]const u8{},
    /// Free variable names
    freevars: []const []const u8 = &[_][]const u8{},
    /// Cell variable names
    cellvars: []const []const u8 = &[_][]const u8{},
    /// Number of arguments
    argcount: u32 = 0,
    /// Number of positional-only arguments
    posonlyargcount: u32 = 0,
    /// Number of keyword-only arguments
    kwonlyargcount: u32 = 0,
    /// Number of local variables
    nlocals: u32 = 0,
    /// Required stack size
    stacksize: u32 = 0,
    /// Code flags
    flags: CodeFlags = .{},
};

// ============================================================================
// Opcodes
// ============================================================================

/// Opcodes used by code generator
pub const Opcode = enum(u8) {
    NOP = 0,
    POP_TOP = 1,
    PUSH_NULL = 2,

    UNARY_NEGATIVE = 11,
    UNARY_NOT = 12,
    UNARY_INVERT = 15,

    BINARY_OP = 22,
    BINARY_SUBSCR = 25,

    STORE_SUBSCR = 60,
    DELETE_SUBSCR = 61,

    GET_ITER = 68,

    RETURN_VALUE = 83,

    STORE_NAME = 90,
    DELETE_NAME = 91,
    UNPACK_SEQUENCE = 92,
    FOR_ITER = 93,

    STORE_ATTR = 95,
    DELETE_ATTR = 96,
    STORE_GLOBAL = 97,
    DELETE_GLOBAL = 98,

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

    JUMP_FORWARD = 110,
    POP_JUMP_IF_FALSE = 114,
    POP_JUMP_IF_TRUE = 115,
    LOAD_GLOBAL = 116,

    LOAD_FAST = 124,
    STORE_FAST = 125,
    DELETE_FAST = 126,

    RAISE_VARARGS = 130,
    MAKE_FUNCTION = 132,
    BUILD_SLICE = 133,

    LOAD_DEREF = 137,
    STORE_DEREF = 138,
    DELETE_DEREF = 139,

    CALL = 171,
};

/// Get stack effect for opcode
fn opcodeStackEffect(opcode: Opcode, arg: u32) i32 {
    return switch (opcode) {
        .NOP => 0,
        .POP_TOP => -1,
        .PUSH_NULL => 1,
        .UNARY_NEGATIVE, .UNARY_NOT, .UNARY_INVERT => 0,
        .BINARY_OP, .BINARY_SUBSCR => -1,
        .STORE_SUBSCR => -3,
        .DELETE_SUBSCR => -2,
        .GET_ITER => 0,
        .RETURN_VALUE => -1,
        .STORE_NAME, .STORE_GLOBAL, .STORE_FAST, .STORE_DEREF => -1,
        .DELETE_NAME, .DELETE_GLOBAL, .DELETE_FAST, .DELETE_DEREF => 0,
        .STORE_ATTR => -2,
        .DELETE_ATTR => -1,
        .LOAD_CONST, .LOAD_NAME, .LOAD_GLOBAL, .LOAD_FAST, .LOAD_DEREF => 1,
        .LOAD_ATTR => 0,
        .COMPARE_OP => -1,
        .IMPORT_NAME => -1,
        .IMPORT_FROM => 1,
        .JUMP_FORWARD => 0,
        .POP_JUMP_IF_FALSE, .POP_JUMP_IF_TRUE => -1,
        .BUILD_TUPLE, .BUILD_LIST, .BUILD_SET => blk: {
            break :blk 1 - @as(i32, @intCast(arg));
        },
        .BUILD_MAP => 1 - @as(i32, @intCast(2 * arg)),
        .UNPACK_SEQUENCE => @as(i32, @intCast(arg)) - 1,
        .FOR_ITER => 1,
        .RAISE_VARARGS => -@as(i32, @intCast(arg)),
        .MAKE_FUNCTION => -@as(i32, @popCount(arg & 0x0F)),
        .BUILD_SLICE => -@as(i32, @intCast(arg)) + 1,
        .CALL => -@as(i32, @intCast(arg)) - 1,
    };
}

// ============================================================================
// Future Features
// ============================================================================

/// Future feature flags
pub const FutureFeatures = packed struct {
    division: bool = false,
    absolute_import: bool = false,
    with_statement: bool = false,
    print_function: bool = false,
    unicode_literals: bool = false,
    barry_as_FLUFL: bool = false,
    generator_stop: bool = false,
    annotations: bool = false,

    _padding: u8 = 0,
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Extract docstring from body
fn getDocstring(body: anytype) ?[]const u8 {
    _ = body;
    // Would check if first statement is a string expression
    return null;
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the codegen module
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

test "compiler unit locals" {
    const allocator = std.testing.allocator;

    var unit = CompilerUnit.init(allocator, "test", .function);
    defer unit.deinit();

    const idx1 = try unit.addLocal("x");
    const idx2 = try unit.addLocal("y");
    const idx3 = try unit.addLocal("x"); // duplicate

    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(u32, 1), idx2);
    try std.testing.expectEqual(@as(u32, 0), idx3); // returns existing
}

test "compiler unit constants" {
    const allocator = std.testing.allocator;

    var unit = CompilerUnit.init(allocator, "test", .function);
    defer unit.deinit();

    const idx1 = try unit.addConst(.{ .integer = 42 });
    const idx2 = try unit.addConst(.{ .string = "hello" });
    const idx3 = try unit.addConst(.{ .integer = 42 }); // duplicate

    try std.testing.expectEqual(@as(u32, 0), idx1);
    try std.testing.expectEqual(@as(u32, 1), idx2);
    try std.testing.expectEqual(@as(u32, 0), idx3);
}

test "stack tracking" {
    const allocator = std.testing.allocator;

    var unit = CompilerUnit.init(allocator, "test", .function);
    defer unit.deinit();

    unit.adjustStack(1); // LOAD_CONST
    unit.adjustStack(1); // LOAD_CONST
    unit.adjustStack(-1); // BINARY_OP

    try std.testing.expectEqual(@as(i32, 1), unit.stack_depth);
    try std.testing.expectEqual(@as(i32, 2), unit.max_stack_depth);
}

test "code generator scopes" {
    const allocator = std.testing.allocator;

    var gen = CodeGenerator.init(allocator, "test.py");
    defer gen.deinit();

    try gen.enterScope("<module>", .module);
    try std.testing.expect(gen.unit != null);
    try std.testing.expectEqual(ScopeType.module, gen.unit.?.scope_type);

    try gen.enterScope("func", .function);
    try std.testing.expectEqual(ScopeType.function, gen.unit.?.scope_type);
    try std.testing.expect(gen.unit.?.parent != null);

    _ = gen.exitScope();
    try std.testing.expectEqual(ScopeType.module, gen.unit.?.scope_type);
}

test "opcode stack effects" {
    try std.testing.expectEqual(@as(i32, 1), opcodeStackEffect(.LOAD_CONST, 0));
    try std.testing.expectEqual(@as(i32, -1), opcodeStackEffect(.POP_TOP, 0));
    try std.testing.expectEqual(@as(i32, -1), opcodeStackEffect(.BINARY_OP, 0));
    try std.testing.expectEqual(@as(i32, -2), opcodeStackEffect(.BUILD_TUPLE, 3)); // 1 - 3
    try std.testing.expectEqual(@as(i32, -5), opcodeStackEffect(.BUILD_MAP, 3)); // 1 - 6
}

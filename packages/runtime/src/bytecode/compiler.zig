/// Bytecode Compiler - Compiles Python AST to bytecode for the VM
///
/// This compiler takes metal0's AST and produces CodeObject bytecode
/// that can be executed by the bytecode VM.
const std = @import("std");
const Allocator = std.mem.Allocator;
const opcodes = @import("opcodes.zig");
const Opcode = opcodes.Opcode;
const encodeVarInt = opcodes.encodeVarInt;
const frame = @import("frame.zig");
const CodeObject = frame.CodeObject;
const CodeFlags = frame.CodeFlags;
const PyValue = frame.PyValue;

/// Compiler error types
pub const CompileError = error{
    OutOfMemory,
    InvalidSyntax,
    UnsupportedNode,
    TooManyConstants,
    TooManyLocals,
    TooManyNames,
    JumpTooFar,
    BreakOutsideLoop,
    ContinueOutsideLoop,
    ReturnOutsideFunction,
};

/// Scope type for variable resolution
pub const ScopeType = enum {
    module,
    function,
    class,
    comprehension,
};

/// Variable scope information
pub const VarScope = enum {
    local,
    global,
    free,
    cell,
};

/// Loop context for break/continue
const LoopContext = struct {
    start: u32,
    break_patches: std.ArrayList(u32),
    continue_patches: std.ArrayList(u32),
};

/// Bytecode compiler state
pub const Compiler = struct {
    allocator: Allocator,

    /// Emitted bytecode
    bytecode: std.ArrayList(u8),

    /// Constant pool
    constants: std.ArrayList(PyValue),

    /// Local variable names
    varnames: std.ArrayList([]const u8),

    /// Free variable names (from enclosing scope)
    freevars: std.ArrayList([]const u8),

    /// Cell variable names (captured by nested functions)
    cellvars: std.ArrayList([]const u8),

    /// Global/attribute names
    names: std.ArrayList([]const u8),

    /// Current scope type
    scope_type: ScopeType,

    /// Loop stack for break/continue
    loop_stack: std.ArrayList(LoopContext),

    /// Source filename
    filename: []const u8,

    /// Function name
    name: []const u8,

    /// First line number
    firstlineno: u32,

    /// Code flags
    flags: CodeFlags,

    /// Argument count (for functions)
    argcount: u16,

    /// Initialize compiler
    pub fn init(allocator: Allocator) Compiler {
        return .{
            .allocator = allocator,
            .bytecode = .{},
            .constants = .{},
            .varnames = .{},
            .freevars = .{},
            .cellvars = .{},
            .names = .{},
            .scope_type = .module,
            .loop_stack = .{},
            .filename = "<unknown>",
            .name = "<module>",
            .firstlineno = 1,
            .flags = .{},
            .argcount = 0,
        };
    }

    /// Clean up compiler resources
    pub fn deinit(self: *Compiler) void {
        self.bytecode.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.varnames.deinit(self.allocator);
        self.freevars.deinit(self.allocator);
        self.cellvars.deinit(self.allocator);
        self.names.deinit(self.allocator);
        for (self.loop_stack.items) |*loop| {
            loop.break_patches.deinit(self.allocator);
            loop.continue_patches.deinit(self.allocator);
        }
        self.loop_stack.deinit(self.allocator);
    }

    /// Finalize and return CodeObject
    pub fn finalize(self: *Compiler) !*const CodeObject {
        const code = try self.allocator.create(CodeObject);
        code.* = .{
            .bytecode = try self.bytecode.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .varnames = try self.varnames.toOwnedSlice(self.allocator),
            .freevars = try self.freevars.toOwnedSlice(self.allocator),
            .cellvars = try self.cellvars.toOwnedSlice(self.allocator),
            .names = try self.names.toOwnedSlice(self.allocator),
            .nlocals = @intCast(self.varnames.items.len),
            .stacksize = 256, // Conservative estimate
            .argcount = self.argcount,
            .flags = self.flags,
            .filename = self.filename,
            .name = self.name,
            .firstlineno = self.firstlineno,
        };
        return code;
    }

    // ========================================
    // Bytecode emission helpers
    // ========================================

    /// Current bytecode offset
    fn offset(self: *const Compiler) u32 {
        return @intCast(self.bytecode.items.len);
    }

    /// Emit a single opcode with no argument
    fn emit(self: *Compiler, op: Opcode) !void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
    }

    /// Emit opcode with varint-encoded argument
    fn emitArg(self: *Compiler, op: Opcode, arg: u8) !void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        // For small values (<= 127), varint is just the byte itself
        try self.bytecode.append(self.allocator, arg);
    }

    /// Emit opcode with varint-encoded u32 argument
    fn emitArgU32(self: *Compiler, op: Opcode, arg: u32) !void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        var buf: [5]u8 = undefined;
        const size = encodeVarInt(arg, &buf);
        for (buf[0..size]) |byte| {
            try self.bytecode.append(self.allocator, byte);
        }
    }

    /// Emit opcode with 2-byte varint argument (for jumps with known target)
    fn emitArg2Byte(self: *Compiler, op: Opcode, arg: u32) !void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        // Always 2-byte varint encoding
        try self.bytecode.append(self.allocator, @intCast((arg & 0x7F) | 0x80));
        try self.bytecode.append(self.allocator, @intCast((arg >> 7) & 0x7F));
    }

    /// Emit jump with placeholder (returns offset of jump target bytes)
    /// Uses 2-byte placeholder for varint (handles targets up to 16383)
    fn emitJump(self: *Compiler, op: Opcode) !u32 {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        const patch_offset = self.offset();
        // Reserve 2 bytes for varint (most jumps are < 16383)
        try self.bytecode.append(self.allocator, 0);
        try self.bytecode.append(self.allocator, 0);
        return patch_offset;
    }

    /// Patch jump target at offset (always 2-byte varint encoding)
    fn patchJump(self: *Compiler, patch_offset: u32, target: u32) void {
        // Always encode as 2-byte varint to maintain consistent bytecode size
        // First byte: low 7 bits + continuation bit
        // Second byte: next 7 bits (no continuation bit)
        self.bytecode.items[patch_offset] = @intCast((target & 0x7F) | 0x80);
        self.bytecode.items[patch_offset + 1] = @intCast((target >> 7) & 0x7F);
    }

    /// Patch jump to current offset
    pub fn patchJumpHere(self: *Compiler, patch_offset: u32) void {
        self.patchJump(patch_offset, self.offset());
    }

    // ========================================
    // Constant pool management
    // ========================================

    /// Add constant to pool, return index
    fn addConstant(self: *Compiler, value: PyValue) !u8 {
        // Check for existing constant
        for (self.constants.items, 0..) |c, i| {
            if (self.constantsEqual(c, value)) {
                return @intCast(i);
            }
        }
        if (self.constants.items.len >= 256) {
            return CompileError.TooManyConstants;
        }
        const idx = self.constants.items.len;
        try self.constants.append(self.allocator, value);
        return @intCast(idx);
    }

    /// Check if two constants are equal
    fn constantsEqual(self: *Compiler, a: PyValue, b: PyValue) bool {
        _ = self;
        return switch (a) {
            .none => b == .none,
            .bool => |av| b == .bool and b.bool == av,
            .int => |av| b == .int and b.int == av,
            .float => |av| b == .float and b.float == av,
            .string => |av| b == .string and std.mem.eql(u8, av, b.string),
            else => false,
        };
    }

    /// Add integer constant
    fn addIntConstant(self: *Compiler, value: i64) !u8 {
        return self.addConstant(.{ .int = value });
    }

    /// Add float constant
    fn addFloatConstant(self: *Compiler, value: f64) !u8 {
        return self.addConstant(.{ .float = value });
    }

    /// Add string constant
    fn addStringConstant(self: *Compiler, value: []const u8) !u8 {
        return self.addConstant(.{ .string = value });
    }

    /// Add None constant
    fn addNoneConstant(self: *Compiler) !u8 {
        return self.addConstant(.{ .none = {} });
    }

    // ========================================
    // Name management
    // ========================================

    /// Add local variable name
    fn addLocal(self: *Compiler, name: []const u8) !u8 {
        for (self.varnames.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        if (self.varnames.items.len >= 256) {
            return CompileError.TooManyLocals;
        }
        const idx = self.varnames.items.len;
        try self.varnames.append(self.allocator, name);
        return @intCast(idx);
    }

    /// Add global/attribute name
    fn addName(self: *Compiler, name: []const u8) !u8 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        if (self.names.items.len >= 256) {
            return CompileError.TooManyNames;
        }
        const idx = self.names.items.len;
        try self.names.append(self.allocator, name);
        return @intCast(idx);
    }

    // ========================================
    // Loop management
    // ========================================

    /// Enter a loop
    fn enterLoop(self: *Compiler) !void {
        try self.loop_stack.append(self.allocator, .{
            .start = self.offset(),
            .break_patches = .{},
            .continue_patches = .{},
        });
    }

    /// Exit loop and patch all breaks/continues
    fn exitLoop(self: *Compiler) void {
        if (self.loop_stack.items.len == 0) return;
        var loop = self.loop_stack.pop() orelse return;

        // Patch all break statements to current offset
        for (loop.break_patches.items) |patch| {
            self.patchJumpHere(patch);
        }

        // Continue patches should already be patched to loop start
        loop.break_patches.deinit(self.allocator);
        loop.continue_patches.deinit(self.allocator);
    }

    /// Record break statement (returns error if outside loop)
    fn recordBreak(self: *Compiler) !u32 {
        if (self.loop_stack.items.len == 0) {
            return CompileError.BreakOutsideLoop;
        }
        const patch = try self.emitJump(.JUMP);
        try self.loop_stack.items[self.loop_stack.items.len - 1].break_patches.append(self.allocator, patch);
        return patch;
    }

    /// Record continue statement (returns error if outside loop)
    fn recordContinue(self: *Compiler) !void {
        if (self.loop_stack.items.len == 0) {
            return CompileError.ContinueOutsideLoop;
        }
        const loop_start = self.loop_stack.items[self.loop_stack.items.len - 1].start;
        try self.emitArg2Byte(.JUMP, loop_start);
    }

    // ========================================
    // High-level compilation (for simple expressions)
    // ========================================

    /// Compile a simple integer expression
    pub fn compileInt(self: *Compiler, value: i64) !void {
        // Use LOAD_I8 for small integers
        if (value >= -128 and value <= 127) {
            try self.emitArg(.LOAD_I8, @bitCast(@as(i8, @intCast(value))));
        } else {
            const idx = try self.addIntConstant(value);
            try self.emitArg(.LOAD_CONST, idx);
        }
    }

    /// Compile a float
    pub fn compileFloat(self: *Compiler, value: f64) !void {
        const idx = try self.addFloatConstant(value);
        try self.emitArg(.LOAD_CONST, idx);
    }

    /// Compile a string
    pub fn compileString(self: *Compiler, value: []const u8) !void {
        const idx = try self.addStringConstant(value);
        try self.emitArg(.LOAD_CONST, idx);
    }

    /// Compile None
    pub fn compileNone(self: *Compiler) !void {
        try self.emit(.LOAD_NONE);
    }

    /// Compile True
    pub fn compileTrue(self: *Compiler) !void {
        try self.emit(.LOAD_TRUE);
    }

    /// Compile False
    pub fn compileFalse(self: *Compiler) !void {
        try self.emit(.LOAD_FALSE);
    }

    /// Compile binary operation (assumes operands already on stack)
    pub fn compileBinOp(self: *Compiler, op: BinOpType) !void {
        try self.emit(switch (op) {
            .add => .ADD,
            .sub => .SUB,
            .mul => .MUL,
            .div => .DIV,
            .floordiv => .FLOORDIV,
            .mod => .MOD,
            .pow => .POW,
            .lshift => .LSHIFT,
            .rshift => .RSHIFT,
            .band => .AND,
            .bor => .OR,
            .bxor => .XOR,
            .matmul => .MATMUL,
        });
    }

    /// Compile unary operation (assumes operand on stack)
    pub fn compileUnaryOp(self: *Compiler, op: UnaryOpType) !void {
        try self.emit(switch (op) {
            .neg => .NEG,
            .pos => .POS,
            .not => .NOT,
            .invert => .INVERT,
        });
    }

    /// Compile comparison (assumes operands on stack)
    pub fn compileCompare(self: *Compiler, op: CompareOpType) !void {
        try self.emit(switch (op) {
            .lt => .LT,
            .le => .LE,
            .eq => .EQ,
            .ne => .NE,
            .gt => .GT,
            .ge => .GE,
            .is => .IS,
            .is_not => .IS_NOT,
            .in => .IN,
            .not_in => .NOT_IN,
        });
    }

    /// Compile load local variable
    pub fn compileLoadLocal(self: *Compiler, name: []const u8) !void {
        const idx = try self.addLocal(name);
        try self.emitArg(.LOAD_FAST, idx);
    }

    /// Compile store local variable
    pub fn compileStoreLocal(self: *Compiler, name: []const u8) !void {
        const idx = try self.addLocal(name);
        try self.emitArg(.STORE_FAST, idx);
    }

    /// Compile load global variable
    pub fn compileLoadGlobal(self: *Compiler, name: []const u8) !void {
        const idx = try self.addName(name);
        try self.emitArg(.LOAD_GLOBAL, idx);
    }

    /// Compile store global variable
    pub fn compileStoreGlobal(self: *Compiler, name: []const u8) !void {
        const idx = try self.addName(name);
        try self.emitArg(.STORE_GLOBAL, idx);
    }

    /// Compile load attribute
    pub fn compileLoadAttr(self: *Compiler, name: []const u8) !void {
        const idx = try self.addName(name);
        try self.emitArg(.LOAD_ATTR, idx);
    }

    /// Compile store attribute
    pub fn compileStoreAttr(self: *Compiler, name: []const u8) !void {
        const idx = try self.addName(name);
        try self.emitArg(.STORE_ATTR, idx);
    }

    /// Compile function call
    pub fn compileCall(self: *Compiler, argc: u8) !void {
        try self.emitArg(.CALL, argc);
    }

    /// Compile return
    pub fn compileReturn(self: *Compiler) !void {
        try self.emit(.RETURN);
    }

    /// Compile return None (implicit)
    pub fn compileReturnNone(self: *Compiler) !void {
        try self.emit(.LOAD_NONE);
        try self.emit(.RETURN);
    }

    /// Compile BUILD_LIST
    pub fn compileBuildList(self: *Compiler, count: u8) !void {
        try self.emitArg(.BUILD_LIST, count);
    }

    /// Compile BUILD_TUPLE
    pub fn compileBuildTuple(self: *Compiler, count: u8) !void {
        try self.emitArg(.BUILD_TUPLE, count);
    }

    /// Compile BUILD_DICT
    pub fn compileBuildDict(self: *Compiler, count: u8) !void {
        try self.emitArg(.BUILD_DICT, count);
    }

    /// Compile BUILD_SET
    pub fn compileBuildSet(self: *Compiler, count: u8) !void {
        try self.emitArg(.BUILD_SET, count);
    }

    /// Compile subscript load (TOS1[TOS])
    pub fn compileSubscriptLoad(self: *Compiler) !void {
        try self.emit(.BINARY_SUBSCR);
    }

    /// Compile subscript store (TOS2[TOS1] = TOS)
    pub fn compileSubscriptStore(self: *Compiler) !void {
        try self.emit(.STORE_SUBSCR);
    }

    /// Compile GET_ITER
    pub fn compileGetIter(self: *Compiler) !void {
        try self.emit(.GET_ITER);
    }

    /// Compile FOR_ITER with jump offset
    pub fn compileForIter(self: *Compiler) !u32 {
        return self.emitJump(.FOR_ITER);
    }

    /// Compile conditional jump if false
    pub fn compileJumpIfFalse(self: *Compiler) !u32 {
        return self.emitJump(.JUMP_IF_FALSE);
    }

    /// Compile conditional jump if true
    pub fn compileJumpIfTrue(self: *Compiler) !u32 {
        return self.emitJump(.JUMP_IF_TRUE);
    }

    /// Compile unconditional jump
    pub fn compileJump(self: *Compiler) !u32 {
        return self.emitJump(.JUMP);
    }

    /// Compile POP
    pub fn compilePop(self: *Compiler) !void {
        try self.emit(.POP);
    }

    /// Compile DUP
    pub fn compileDup(self: *Compiler) !void {
        try self.emit(.DUP);
    }
};

/// Binary operation types
pub const BinOpType = enum {
    add,
    sub,
    mul,
    div,
    floordiv,
    mod,
    pow,
    lshift,
    rshift,
    band,
    bor,
    bxor,
    matmul,
};

/// Unary operation types
pub const UnaryOpType = enum {
    neg,
    pos,
    not,
    invert,
};

/// Comparison operation types
pub const CompareOpType = enum {
    lt,
    le,
    eq,
    ne,
    gt,
    ge,
    is,
    is_not,
    in,
    not_in,
};

// ========================================
// Tests
// ========================================

test "compiler init and finalize" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Compile simple expression: 42
    try compiler.compileInt(42);
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    // Should have LOAD_I8 42, RETURN
    try std.testing.expectEqual(@as(usize, 3), code.bytecode.len);
    try std.testing.expectEqual(@intFromEnum(Opcode.LOAD_I8), code.bytecode[0]);
    try std.testing.expectEqual(@as(u8, 42), code.bytecode[1]);
    try std.testing.expectEqual(@intFromEnum(Opcode.RETURN), code.bytecode[2]);
}

test "compiler arithmetic" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Compile: 1 + 2
    try compiler.compileInt(1);
    try compiler.compileInt(2);
    try compiler.compileBinOp(.add);
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    // LOAD_I8 1, LOAD_I8 2, ADD, RETURN
    try std.testing.expectEqual(@as(usize, 6), code.bytecode.len);
}

test "compiler variables" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Compile: x = 42
    try compiler.compileInt(42);
    try compiler.compileStoreLocal("x");
    try compiler.compileLoadLocal("x");
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    try std.testing.expectEqual(@as(usize, 1), code.varnames.len);
    try std.testing.expectEqualStrings("x", code.varnames[0]);
}

test "compiler constants" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Compile: 1000000
    try compiler.compileInt(1000000);
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    // Large int should use LOAD_CONST
    try std.testing.expectEqual(@intFromEnum(Opcode.LOAD_CONST), code.bytecode[0]);
    try std.testing.expectEqual(@as(usize, 1), code.constants.len);
    try std.testing.expectEqual(@as(i64, 1000000), code.constants[0].int);
}

test "compiler jumps" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Compile: if True: 1 else: 2
    try compiler.compileTrue();
    const else_jump = try compiler.compileJumpIfFalse();
    try compiler.compileInt(1);
    const end_jump = try compiler.compileJump();
    compiler.patchJumpHere(else_jump);
    try compiler.compileInt(2);
    compiler.patchJumpHere(end_jump);
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    // Should have valid bytecode with jumps
    try std.testing.expect(code.bytecode.len > 5);
}

test "compiler loop" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Simulate: while True: break
    try compiler.enterLoop();
    try compiler.compileTrue();
    const exit_jump = try compiler.compileJumpIfFalse();
    _ = try compiler.recordBreak();
    try compiler.recordContinue();
    compiler.patchJumpHere(exit_jump);
    compiler.exitLoop();
    try compiler.compileReturn();

    const code = try compiler.finalize();
    defer allocator.destroy(code);
    defer allocator.free(code.bytecode);
    defer allocator.free(code.constants);
    defer allocator.free(code.varnames);
    defer allocator.free(code.freevars);
    defer allocator.free(code.cellvars);
    defer allocator.free(code.names);

    try std.testing.expect(code.bytecode.len > 0);
}

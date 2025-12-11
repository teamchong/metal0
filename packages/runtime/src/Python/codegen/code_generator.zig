/// code_generator - Code Generation Engine
/// Mirrors cpython/Python/codegen.c code generator
///
/// Main code generator that transforms AST into bytecode.

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const compiler_unit = @import("compiler_unit.zig");
const code_object = @import("code_object.zig");
const opcode = @import("opcode.zig");

pub const CompileFlags = types.CompileFlags;
pub const ScopeType = types.ScopeType;
pub const FutureFeatures = types.FutureFeatures;
pub const CompilerUnit = compiler_unit.CompilerUnit;
pub const CodeObject = code_object.CodeObject;
pub const Opcode = opcode.Opcode;
pub const opcodeStackEffect = opcode.opcodeStackEffect;

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
            .unit_stack = .{},
        };
    }

    /// Free code generator
    pub fn deinit(self: *Self) void {
        // Clean up current unit if present
        if (self.unit) |unit| {
            unit.deinit();
            self.allocator.destroy(unit);
        }

        // Clean up stacked units
        for (self.unit_stack.items) |unit| {
            unit.deinit();
            self.allocator.destroy(unit);
        }
        self.unit_stack.deinit(self.allocator);
    }

    /// Enter a new scope
    pub fn enterScope(self: *Self, name: []const u8, scope_type: ScopeType) !void {
        const unit = try self.allocator.create(CompilerUnit);
        unit.* = CompilerUnit.init(self.allocator, name, scope_type);
        unit.parent = self.unit;

        if (self.unit) |current| {
            try self.unit_stack.append(self.allocator, current);
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
    pub fn compileStatement(_: *Self, _: anytype) !void {
        // Dispatch based on statement type
        // This would normally pattern match on the AST node type
    }

    /// Compile expression
    pub fn compileExpression(_: *Self, _: anytype) !void {
        // Dispatch based on expression type
    }

    /// Emit instruction
    pub fn emit(self: *Self, op: Opcode, arg: u32) !void {
        if (self.unit) |unit| {
            // Track stack effect
            const effect = opcodeStackEffect(op, arg);
            unit.adjustStack(effect);
        }
        // Would emit to instruction stream
    }

    /// Emit instruction with source location
    pub fn emitWithLocation(self: *Self, op: Opcode, arg: u32, lineno: i32, col: i32) !void {
        if (self.unit) |unit| {
            unit.lineno = lineno;
            unit.col_offset = col;
        }
        try self.emit(op, arg);
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

    // exitScope returns the exited unit - caller must clean it up
    if (gen.exitScope()) |exited_unit| {
        defer {
            exited_unit.deinit();
            allocator.destroy(exited_unit);
        }
        try std.testing.expectEqual(ScopeType.module, gen.unit.?.scope_type);
    }
}

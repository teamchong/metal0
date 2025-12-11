/// compiler_unit - Compilation Unit
/// Mirrors cpython/Python/codegen.c compiler unit
///
/// Represents one compilation scope (module, function, class, etc).

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const constant = @import("constant.zig");

pub const ScopeType = types.ScopeType;
pub const CodeFlags = types.CodeFlags;
pub const Constant = constant.Constant;

// ============================================================================
// Compiler Unit
// ============================================================================

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
            .varnames = .{},
            .cellvars = .{},
            .freevars = .{},
            .consts = .{},
            .names = .{},
            .allocator = allocator,
        };
    }

    /// Free compiler unit
    pub fn deinit(self: *Self) void {
        self.varnames.deinit(self.allocator);
        self.cellvars.deinit(self.allocator);
        self.freevars.deinit(self.allocator);
        self.consts.deinit(self.allocator);
        self.names.deinit(self.allocator);
    }

    /// Add local variable
    pub fn addLocal(self: *Self, name: []const u8) !u32 {
        for (self.varnames.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.varnames.items.len);
        try self.varnames.append(self.allocator, name);
        return idx;
    }

    /// Add constant
    pub fn addConst(self: *Self, const_value: Constant) !u32 {
        // Check for existing
        for (self.consts.items, 0..) |c, i| {
            if (c.eql(const_value)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.consts.items.len);
        try self.consts.append(self.allocator, const_value);
        return idx;
    }

    /// Add name
    pub fn addName(self: *Self, name: []const u8) !u32 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        const idx: u32 = @intCast(self.names.items.len);
        try self.names.append(self.allocator, name);
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

//! test.test_future_stmt.test_nested - Tests for `from __future__ import nested_scopes`
//!
//! PEP 227 introduced statically nested scopes (closures) in Python 2.1.
//! Before this, Python used flat scopes where inner functions couldn't access
//! variables from enclosing functions. This PEP enabled proper lexical scoping.
//!
//! This module tests closure behavior and scope resolution.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 227: https://peps.python.org/pep-0227/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Scope Types
// ============================================================================

/// Represents a scope level in Python
pub const ScopeType = enum {
    /// Local scope (function body)
    local,
    /// Enclosing scope (outer function, for closures)
    enclosing,
    /// Global scope (module level)
    global,
    /// Builtin scope (Python builtins)
    builtin,

    pub fn name(self: ScopeType) []const u8 {
        return switch (self) {
            .local => "local",
            .enclosing => "enclosing",
            .global => "global",
            .builtin => "builtin",
        };
    }

    /// Get LEGB priority (lower = higher priority)
    pub fn priority(self: ScopeType) u8 {
        return switch (self) {
            .local => 0,
            .enclosing => 1,
            .global => 2,
            .builtin => 3,
        };
    }
};

// ============================================================================
// Variable Binding
// ============================================================================

/// Represents a variable binding in a scope
pub const Binding = struct {
    name: []const u8,
    value: Value,
    scope: ScopeType,
    is_cell: bool = false, // True if captured by closure
    is_free: bool = false, // True if from enclosing scope

    const Self = @This();

    pub fn init(name_str: []const u8, val: Value, scope: ScopeType) Self {
        return .{
            .name = name_str,
            .value = val,
            .scope = scope,
        };
    }

    /// Mark this binding as captured by a closure
    pub fn markAsCell(self: *Self) void {
        self.is_cell = true;
    }

    /// Mark this binding as coming from enclosing scope
    pub fn markAsFree(self: *Self) void {
        self.is_free = true;
    }
};

/// Simple value type for scope testing
pub const Value = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    none: void,
    function: *const fn () Value,

    pub fn toInt(self: Value) ?i64 {
        return switch (self) {
            .int => |i| i,
            else => null,
        };
    }

    pub fn toFloat(self: Value) ?f64 {
        return switch (self) {
            .float => |f| f,
            .int => |i| @floatFromInt(i),
            else => null,
        };
    }
};

// ============================================================================
// Scope Implementation
// ============================================================================

/// Represents a single scope
pub const Scope = struct {
    scope_type: ScopeType,
    bindings: std.StringHashMap(Binding),
    parent: ?*Scope = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, scope_type: ScopeType) Self {
        return .{
            .scope_type = scope_type,
            .bindings = std.StringHashMap(Binding).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bindings.deinit();
    }

    /// Define a variable in this scope
    pub fn define(self: *Self, name: []const u8, value: Value) !void {
        const binding = Binding.init(name, value, self.scope_type);
        try self.bindings.put(name, binding);
    }

    /// Look up a variable in this scope only
    pub fn get(self: Self, name: []const u8) ?Binding {
        return self.bindings.get(name);
    }

    /// Look up a variable following LEGB rule
    pub fn resolve(self: *Self, name: []const u8) ?Binding {
        // Check local scope
        if (self.get(name)) |binding| {
            return binding;
        }
        // Check parent scopes (enclosing)
        if (self.parent) |parent| {
            return parent.resolve(name);
        }
        return null;
    }

    /// Set parent scope (for nested scopes)
    pub fn setParent(self: *Self, parent: *Scope) void {
        self.parent = parent;
    }

    /// Count bindings in this scope
    pub fn count(self: Self) usize {
        return self.bindings.count();
    }
};

// ============================================================================
// Closure Implementation
// ============================================================================

/// Represents a closure (function with captured variables)
pub const Closure = struct {
    /// The function code
    func: *const fn (*Closure) Value,
    /// Captured variables from enclosing scopes
    captured: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, func: *const fn (*Closure) Value) Self {
        return .{
            .func = func,
            .captured = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.captured.deinit();
    }

    /// Capture a variable from enclosing scope
    pub fn capture(self: *Self, name: []const u8, value: Value) !void {
        try self.captured.put(name, value);
    }

    /// Get a captured variable
    pub fn getCapture(self: Self, name: []const u8) ?Value {
        return self.captured.get(name);
    }

    /// Call the closure
    pub fn call(self: *Self) Value {
        return self.func(self);
    }

    /// Number of captured variables
    pub fn captureCount(self: Self) usize {
        return self.captured.count();
    }
};

// ============================================================================
// Cell and Free Variables
// ============================================================================

/// Cell variable - a variable that is captured by nested function
pub const CellVar = struct {
    name: []const u8,
    value: *Value,

    const Self = @This();

    pub fn init(name_str: []const u8, value_ptr: *Value) Self {
        return .{ .name = name_str, .value = value_ptr };
    }

    pub fn get(self: Self) Value {
        return self.value.*;
    }

    pub fn set(self: *Self, value: Value) void {
        self.value.* = value;
    }
};

/// Free variable - a reference to an enclosing scope's variable
pub const FreeVar = struct {
    name: []const u8,
    cell: *CellVar,

    const Self = @This();

    pub fn init(name_str: []const u8, cell: *CellVar) Self {
        return .{ .name = name_str, .cell = cell };
    }

    pub fn get(self: Self) Value {
        return self.cell.get();
    }

    pub fn set(self: *Self, value: Value) void {
        self.cell.set(value);
    }
};

// ============================================================================
// Nonlocal Statement Support
// ============================================================================

/// Tracks nonlocal declarations
pub const NonlocalTracker = struct {
    nonlocals: std.StringHashMap(ScopeType),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .nonlocals = std.StringHashMap(ScopeType).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.nonlocals.deinit();
    }

    /// Declare a variable as nonlocal
    pub fn declareNonlocal(self: *Self, name: []const u8) !void {
        try self.nonlocals.put(name, .enclosing);
    }

    /// Check if a variable is declared nonlocal
    pub fn isNonlocal(self: Self, name: []const u8) bool {
        return self.nonlocals.contains(name);
    }

    /// Get the scope type for a variable
    pub fn getScopeType(self: Self, name: []const u8) ScopeType {
        if (self.nonlocals.get(name)) |scope| {
            return scope;
        }
        return .local;
    }
};

// ============================================================================
// Scope Analyzer
// ============================================================================

/// Analyzes scope for name resolution
pub const ScopeAnalyzer = struct {
    scopes: std.ArrayListUnmanaged(*Scope),
    cell_vars: std.StringHashMap(void),
    free_vars: std.StringHashMap(void),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .scopes = .{},
            .cell_vars = std.StringHashMap(void).init(allocator),
            .free_vars = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scopes.deinit(self.allocator);
        self.cell_vars.deinit();
        self.free_vars.deinit();
    }

    /// Push a new scope
    pub fn pushScope(self: *Self, scope: *Scope) !void {
        try self.scopes.append(self.allocator, scope);
    }

    /// Pop the current scope
    pub fn popScope(self: *Self) ?*Scope {
        if (self.scopes.items.len == 0) return null;
        return self.scopes.pop();
    }

    /// Get the current scope
    pub fn currentScope(self: Self) ?*Scope {
        if (self.scopes.items.len == 0) return null;
        return self.scopes.items[self.scopes.items.len - 1];
    }

    /// Mark a variable as cell var
    pub fn markCellVar(self: *Self, name: []const u8) !void {
        try self.cell_vars.put(name, {});
    }

    /// Mark a variable as free var
    pub fn markFreeVar(self: *Self, name: []const u8) !void {
        try self.free_vars.put(name, {});
    }

    /// Check if variable is a cell var
    pub fn isCellVar(self: Self, name: []const u8) bool {
        return self.cell_vars.contains(name);
    }

    /// Check if variable is a free var
    pub fn isFreeVar(self: Self, name: []const u8) bool {
        return self.free_vars.contains(name);
    }

    /// Get current nesting depth
    pub fn depth(self: Self) usize {
        return self.scopes.items.len;
    }
};

// ============================================================================
// Closure Factory
// ============================================================================

/// Factory for creating closures with proper scope handling
pub const ClosureFactory = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Create a counter closure (classic closure example)
    pub fn makeCounter(self: Self, start: i64) !Closure {
        var closure = Closure.init(self.allocator, dummyFunc);
        try closure.capture("count", .{ .int = start });
        return closure;
    }

    fn dummyFunc(_: *Closure) Value {
        return .{ .int = 0 };
    }

    /// Create an adder closure
    pub fn makeAdder(self: Self, x: i64) !Closure {
        var closure = Closure.init(self.allocator, dummyFunc);
        try closure.capture("x", .{ .int = x });
        return closure;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "scope_type_names" {
    try testing.expectEqualStrings("local", ScopeType.local.name());
    try testing.expectEqualStrings("enclosing", ScopeType.enclosing.name());
    try testing.expectEqualStrings("global", ScopeType.global.name());
    try testing.expectEqualStrings("builtin", ScopeType.builtin.name());
}

test "scope_type_priority" {
    try testing.expect(ScopeType.local.priority() < ScopeType.enclosing.priority());
    try testing.expect(ScopeType.enclosing.priority() < ScopeType.global.priority());
    try testing.expect(ScopeType.global.priority() < ScopeType.builtin.priority());
}

test "binding_creation" {
    var binding = Binding.init("x", .{ .int = 42 }, .local);
    try testing.expectEqualStrings("x", binding.name);
    try testing.expectEqual(@as(i64, 42), binding.value.toInt().?);
    try testing.expect(!binding.is_cell);
    try testing.expect(!binding.is_free);
}

test "binding_mark_cell" {
    var binding = Binding.init("x", .{ .int = 0 }, .local);
    binding.markAsCell();
    try testing.expect(binding.is_cell);
}

test "binding_mark_free" {
    var binding = Binding.init("y", .{ .int = 0 }, .enclosing);
    binding.markAsFree();
    try testing.expect(binding.is_free);
}

test "scope_define_and_get" {
    var scope = Scope.init(testing.allocator, .local);
    defer scope.deinit();

    try scope.define("x", .{ .int = 10 });
    try scope.define("y", .{ .float = 3.14 });

    try testing.expectEqual(@as(usize, 2), scope.count());
    try testing.expectEqual(@as(i64, 10), scope.get("x").?.value.toInt().?);
}

test "scope_resolve_local" {
    var scope = Scope.init(testing.allocator, .local);
    defer scope.deinit();

    try scope.define("x", .{ .int = 42 });
    const resolved = scope.resolve("x");
    try testing.expect(resolved != null);
    try testing.expectEqual(@as(i64, 42), resolved.?.value.toInt().?);
}

test "scope_resolve_parent" {
    var parent = Scope.init(testing.allocator, .global);
    defer parent.deinit();
    try parent.define("global_var", .{ .int = 100 });

    var child = Scope.init(testing.allocator, .local);
    defer child.deinit();
    child.setParent(&parent);

    const resolved = child.resolve("global_var");
    try testing.expect(resolved != null);
    try testing.expectEqual(@as(i64, 100), resolved.?.value.toInt().?);
}

test "scope_local_shadows_parent" {
    var parent = Scope.init(testing.allocator, .global);
    defer parent.deinit();
    try parent.define("x", .{ .int = 100 });

    var child = Scope.init(testing.allocator, .local);
    defer child.deinit();
    child.setParent(&parent);
    try child.define("x", .{ .int = 1 });

    // Local should shadow global
    try testing.expectEqual(@as(i64, 1), child.resolve("x").?.value.toInt().?);
}

test "closure_capture" {
    var closure = Closure.init(testing.allocator, testDummyFunc);
    defer closure.deinit();

    try closure.capture("x", .{ .int = 42 });
    try closure.capture("y", .{ .float = 3.14 });

    try testing.expectEqual(@as(usize, 2), closure.captureCount());
    try testing.expectEqual(@as(i64, 42), closure.getCapture("x").?.toInt().?);
}

fn testDummyFunc(_: *Closure) Value {
    return .{ .int = 0 };
}

test "nonlocal_tracker" {
    var tracker = NonlocalTracker.init(testing.allocator);
    defer tracker.deinit();

    try testing.expect(!tracker.isNonlocal("x"));

    try tracker.declareNonlocal("x");
    try testing.expect(tracker.isNonlocal("x"));
    try testing.expectEqual(ScopeType.enclosing, tracker.getScopeType("x"));
}

test "scope_analyzer_push_pop" {
    var analyzer = ScopeAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    var scope1 = Scope.init(testing.allocator, .global);
    defer scope1.deinit();
    var scope2 = Scope.init(testing.allocator, .local);
    defer scope2.deinit();

    try analyzer.pushScope(&scope1);
    try testing.expectEqual(@as(usize, 1), analyzer.depth());

    try analyzer.pushScope(&scope2);
    try testing.expectEqual(@as(usize, 2), analyzer.depth());

    _ = analyzer.popScope();
    try testing.expectEqual(@as(usize, 1), analyzer.depth());
}

test "scope_analyzer_cell_free_vars" {
    var analyzer = ScopeAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.markCellVar("x");
    try analyzer.markFreeVar("y");

    try testing.expect(analyzer.isCellVar("x"));
    try testing.expect(!analyzer.isCellVar("y"));
    try testing.expect(analyzer.isFreeVar("y"));
    try testing.expect(!analyzer.isFreeVar("x"));
}

test "closure_factory_counter" {
    const factory = ClosureFactory.init(testing.allocator);
    var counter = try factory.makeCounter(10);
    defer counter.deinit();

    try testing.expectEqual(@as(i64, 10), counter.getCapture("count").?.toInt().?);
}

test "closure_factory_adder" {
    const factory = ClosureFactory.init(testing.allocator);
    var adder = try factory.makeAdder(5);
    defer adder.deinit();

    try testing.expectEqual(@as(i64, 5), adder.getCapture("x").?.toInt().?);
}

test "value_conversions" {
    const int_val = Value{ .int = 42 };
    const float_val = Value{ .float = 3.14 };
    const string_val = Value{ .string = "hello" };

    try testing.expectEqual(@as(i64, 42), int_val.toInt().?);
    try testing.expectApproxEqAbs(@as(f64, 42.0), int_val.toFloat().?, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 3.14), float_val.toFloat().?, 0.001);
    try testing.expect(string_val.toInt() == null);
}

test "scope_not_found" {
    var scope = Scope.init(testing.allocator, .local);
    defer scope.deinit();

    try testing.expect(scope.resolve("nonexistent") == null);
}

test "scope_current_scope" {
    var analyzer = ScopeAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try testing.expect(analyzer.currentScope() == null);

    var scope = Scope.init(testing.allocator, .local);
    defer scope.deinit();
    try analyzer.pushScope(&scope);

    try testing.expect(analyzer.currentScope() != null);
}

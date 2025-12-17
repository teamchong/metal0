/// EmitContext - Context-aware code emission
///
/// Different contexts require different code patterns:
/// - Statement context: May need semicolons, error handling
/// - Expression context: May need parentheses, wrapping
/// - Function argument: May need type conversion, catching
/// - Return value: May need error propagation
///
/// This module provides the context tracking needed for proper emission.
///
const std = @import("std");
const ZigValue = @import("zig_value.zig").ZigValue;
const ZigType = @import("zig_type.zig").ZigType;
const TypeConfidence = @import("zig_value.zig").TypeConfidence;

/// The context in which a value is being emitted
pub const EmitContext = enum {
    /// Top-level statement (may need semicolon)
    statement,

    /// Inside an expression (may need parens)
    expression,

    /// As a function argument (may need conversion)
    function_arg,

    /// Variable initializer (RHS of assignment)
    initializer,

    /// Condition in if/while/for (must be bool)
    condition,

    /// Return statement value
    return_value,

    /// Array/slice element
    array_element,

    /// Struct field initializer
    struct_field,

    /// Binary operator operand
    binop_operand,

    /// Unary operator operand
    unop_operand,

    /// Index expression (container[index])
    index_expr,

    /// Field access base (obj.field)
    field_base,

    /// Method call receiver (obj.method())
    method_receiver,

    /// Assert/test condition
    assert_condition,

    /// Print argument
    print_arg,

    /// Check if this context typically needs parenthesization for safety
    pub fn needsParens(self: EmitContext) bool {
        return switch (self) {
            .binop_operand, .unop_operand, .condition => true,
            else => false,
        };
    }

    /// Check if this context needs error handling (catch/try)
    pub fn needsErrorHandling(self: EmitContext) bool {
        return switch (self) {
            .statement, .initializer, .return_value => true,
            else => false,
        };
    }

    /// Check if this context can use try (has error return)
    pub fn canUseTry(self: EmitContext) bool {
        return switch (self) {
            .statement, .return_value => true,
            else => false,
        };
    }

    /// Check if void values are allowed in this context
    pub fn allowsVoid(self: EmitContext) bool {
        return switch (self) {
            .statement => true,
            else => false,
        };
    }

    /// Get the precedence level for this context (for parenthesization)
    pub fn precedence(self: EmitContext) u8 {
        return switch (self) {
            .statement => 0,
            .initializer, .return_value, .function_arg => 1,
            .array_element, .struct_field => 2,
            .condition, .assert_condition => 3,
            .binop_operand => 4,
            .unop_operand => 5,
            .field_base, .method_receiver, .index_expr => 6,
            .expression, .print_arg => 1,
        };
    }
};

/// Error handling mode for value emission
pub const ErrorMode = enum {
    /// Propagate errors with try
    propagate,

    /// Catch errors with default value
    catch_default,

    /// Catch errors with custom handler
    catch_handler,

    /// Assert no errors (panic)
    assert_no_error,

    /// Ignore errors (for void returns)
    ignore,
};

/// Configuration for how to emit a value
pub const EmitConfig = struct {
    /// The emission context
    context: EmitContext = .expression,

    /// Error handling mode
    error_mode: ErrorMode = .propagate,

    /// Default value for catch (when error_mode is .catch_default)
    catch_default: ?[]const u8 = null,

    /// Custom error handler (when error_mode is .catch_handler)
    catch_handler: ?[]const u8 = null,

    /// Whether to add parentheses
    force_parens: bool = false,

    /// Whether to emit type annotation
    emit_type: bool = false,

    /// Expected type (for coercion)
    expected_type: ?*const ZigType = null,

    /// Create a statement config
    pub fn forStatement() EmitConfig {
        return .{
            .context = .statement,
            .error_mode = .propagate,
        };
    }

    /// Create an expression config
    pub fn forExpression() EmitConfig {
        return .{
            .context = .expression,
            .error_mode = .propagate,
        };
    }

    /// Create a function argument config
    pub fn forArg() EmitConfig {
        return .{
            .context = .function_arg,
            .error_mode = .propagate,
        };
    }

    /// Create an initializer config
    pub fn forInit() EmitConfig {
        return .{
            .context = .initializer,
            .error_mode = .propagate,
        };
    }

    /// Create a condition config (must produce bool)
    pub fn forCondition() EmitConfig {
        return .{
            .context = .condition,
            .error_mode = .catch_default,
            .catch_default = "false",
        };
    }

    /// Create a return value config
    pub fn forReturn() EmitConfig {
        return .{
            .context = .return_value,
            .error_mode = .propagate,
        };
    }

    /// Create config with catch default
    pub fn withCatchDefault(self: EmitConfig, default: []const u8) EmitConfig {
        var copy = self;
        copy.error_mode = .catch_default;
        copy.catch_default = default;
        return copy;
    }

    /// Create config with forced parentheses
    pub fn withParens(self: EmitConfig) EmitConfig {
        var copy = self;
        copy.force_parens = true;
        return copy;
    }

    /// Create config with expected type
    pub fn withExpectedType(self: EmitConfig, ty: *const ZigType) EmitConfig {
        var copy = self;
        copy.expected_type = ty;
        return copy;
    }
};

/// Scope tracking for code emission
pub const ScopeKind = enum {
    /// Top-level module scope
    module,

    /// Function body
    function,

    /// Struct definition
    struct_def,

    /// If/else branch
    conditional,

    /// Loop body (for/while)
    loop,

    /// Try block
    try_block,

    /// Catch block
    catch_block,

    /// Finally block
    finally_block,

    /// Defer block
    defer_block,

    /// Comptime block
    comptime_block,

    /// Labeled block
    labeled_block,
};

/// Scope context for tracking nested constructs
pub const ScopeContext = struct {
    /// Scope kind
    kind: ScopeKind,

    /// Scope ID (for unique labels)
    id: u32,

    /// Indent level at scope entry
    indent_level: usize,

    /// Whether this scope can use break
    can_break: bool,

    /// Whether this scope can use continue
    can_continue: bool,

    /// Whether this scope can use return
    can_return: bool,

    /// Break label (if applicable)
    break_label: ?[]const u8,

    /// Parent scope (if any)
    parent: ?*const ScopeContext,

    /// Create a module scope
    pub fn module() ScopeContext {
        return .{
            .kind = .module,
            .id = 0,
            .indent_level = 0,
            .can_break = false,
            .can_continue = false,
            .can_return = false,
            .break_label = null,
            .parent = null,
        };
    }

    /// Create a function scope
    pub fn function(id: u32, parent: ?*const ScopeContext) ScopeContext {
        return .{
            .kind = .function,
            .id = id,
            .indent_level = if (parent) |p| p.indent_level + 1 else 1,
            .can_break = false,
            .can_continue = false,
            .can_return = true,
            .break_label = null,
            .parent = parent,
        };
    }

    /// Create a loop scope
    pub fn loop(id: u32, parent: *const ScopeContext, label: ?[]const u8) ScopeContext {
        return .{
            .kind = .loop,
            .id = id,
            .indent_level = parent.indent_level + 1,
            .can_break = true,
            .can_continue = true,
            .can_return = parent.can_return,
            .break_label = label,
            .parent = parent,
        };
    }

    /// Create a conditional scope
    pub fn conditional(id: u32, parent: *const ScopeContext) ScopeContext {
        return .{
            .kind = .conditional,
            .id = id,
            .indent_level = parent.indent_level + 1,
            .can_break = parent.can_break,
            .can_continue = parent.can_continue,
            .can_return = parent.can_return,
            .break_label = parent.break_label,
            .parent = parent,
        };
    }

    /// Create a try scope
    pub fn tryBlock(id: u32, parent: *const ScopeContext) ScopeContext {
        return .{
            .kind = .try_block,
            .id = id,
            .indent_level = parent.indent_level + 1,
            .can_break = parent.can_break,
            .can_continue = parent.can_continue,
            .can_return = parent.can_return,
            .break_label = parent.break_label,
            .parent = parent,
        };
    }

    /// Create a labeled block scope
    pub fn labeledBlock(id: u32, parent: *const ScopeContext, label: []const u8) ScopeContext {
        return .{
            .kind = .labeled_block,
            .id = id,
            .indent_level = parent.indent_level + 1,
            .can_break = true,
            .can_continue = parent.can_continue,
            .can_return = parent.can_return,
            .break_label = label,
            .parent = parent,
        };
    }

    /// Check if inside a loop
    pub fn insideLoop(self: *const ScopeContext) bool {
        var current: ?*const ScopeContext = self;
        while (current) |ctx| {
            if (ctx.kind == .loop) return true;
            if (ctx.kind == .function) return false; // Stop at function boundary
            current = ctx.parent;
        }
        return false;
    }

    /// Check if inside a try block
    pub fn insideTry(self: *const ScopeContext) bool {
        var current: ?*const ScopeContext = self;
        while (current) |ctx| {
            if (ctx.kind == .try_block) return true;
            if (ctx.kind == .function) return false;
            current = ctx.parent;
        }
        return false;
    }

    /// Get the innermost loop scope
    pub fn innerLoop(self: *const ScopeContext) ?*const ScopeContext {
        var current: ?*const ScopeContext = self;
        while (current) |ctx| {
            if (ctx.kind == .loop) return ctx;
            if (ctx.kind == .function) return null;
            current = ctx.parent;
        }
        return null;
    }
};

/// Handle for RAII-style scope management
pub const ScopeHandle = struct {
    id: u32,
    kind: ScopeKind,
    start_pos: usize, // Position in output buffer at scope start

    /// Check if this handle is valid
    pub fn isValid(self: ScopeHandle) bool {
        return self.id != std.math.maxInt(u32);
    }

    /// Invalid handle constant
    pub const invalid = ScopeHandle{
        .id = std.math.maxInt(u32),
        .kind = .module,
        .start_pos = 0,
    };
};

// ============================================
// Tests
// ============================================

test "EmitContext properties" {
    try std.testing.expect(EmitContext.binop_operand.needsParens());
    try std.testing.expect(!EmitContext.statement.needsParens());

    try std.testing.expect(EmitContext.statement.needsErrorHandling());
    try std.testing.expect(!EmitContext.expression.needsErrorHandling());

    try std.testing.expect(EmitContext.statement.canUseTry());
    try std.testing.expect(!EmitContext.function_arg.canUseTry());

    try std.testing.expect(EmitContext.statement.allowsVoid());
    try std.testing.expect(!EmitContext.expression.allowsVoid());
}

test "EmitConfig builders" {
    const stmt = EmitConfig.forStatement();
    try std.testing.expectEqual(EmitContext.statement, stmt.context);
    try std.testing.expectEqual(ErrorMode.propagate, stmt.error_mode);

    const cond = EmitConfig.forCondition();
    try std.testing.expectEqual(EmitContext.condition, cond.context);
    try std.testing.expectEqual(ErrorMode.catch_default, cond.error_mode);
    try std.testing.expectEqualStrings("false", cond.catch_default.?);

    const with_parens = EmitConfig.forExpression().withParens();
    try std.testing.expect(with_parens.force_parens);
}

test "ScopeContext hierarchy" {
    const mod = ScopeContext.module();
    try std.testing.expectEqual(ScopeKind.module, mod.kind);
    try std.testing.expect(!mod.can_return);

    const func = ScopeContext.function(1, &mod);
    try std.testing.expectEqual(ScopeKind.function, func.kind);
    try std.testing.expect(func.can_return);
    try std.testing.expect(!func.can_break);

    const loop_scope = ScopeContext.loop(2, &func, "loop_0");
    try std.testing.expectEqual(ScopeKind.loop, loop_scope.kind);
    try std.testing.expect(loop_scope.can_break);
    try std.testing.expect(loop_scope.can_continue);
    try std.testing.expect(loop_scope.can_return);

    // Test insideLoop
    try std.testing.expect(loop_scope.insideLoop());
    try std.testing.expect(!func.insideLoop());
}

test "ScopeHandle validity" {
    const valid = ScopeHandle{ .id = 5, .kind = .function, .start_pos = 100 };
    try std.testing.expect(valid.isValid());

    const invalid = ScopeHandle.invalid;
    try std.testing.expect(!invalid.isValid());
}

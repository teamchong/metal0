//! Expression Emitter - Safe parenthesization and block wrapping infrastructure
//!
//! This module provides a builder pattern for emitting expressions with correct
//! parenthesization, catch precedence handling, and labeled block generation.
//!
//! ## Problem Solved
//! Manual parenthesis emission is error-prone:
//! - Catch precedence: `expr catch @panic.method()` binds incorrectly
//! - Labeled blocks in tuples: `neg_1: { ... }` parsed as struct field
//! - Manual paren counting leads to mismatches
//!
//! ## Usage
//! ```zig
//! // Wrap expression in parens for method chaining
//! try self.expr().wrap(node);
//!
//! // Emit with catch handler (double-wrapped for chaining)
//! try self.expr().withCatch(node, "@panic(\"OOM\")");
//!
//! // Create labeled block with temp variable
//! var block = try self.expr().labeledBlock("sub", "__base", node);
//! try block.breakWithFmt("__base[{d}]", .{idx});
//! try block.close();
//! ```

const std = @import("std");
const ast = @import("analysis.ast");

/// Forward declaration - will be imported from parent
const NativeCodegen = @import("main/core.zig").NativeCodegen;
const genExpr = @import("expressions.zig").genExpr;
const producesBlockExpression = @import("expressions.zig").producesBlockExpression;

pub const CodegenError = @import("main/core.zig").CodegenError;

/// Expression emitter with safe wrapping utilities
pub const ExprEmitter = struct {
    codegen: *NativeCodegen,

    /// Emit expression wrapped in parentheses
    /// Use when expression result needs to be used with operators/methods
    pub fn wrap(self: *ExprEmitter, expr: ast.Node) CodegenError!void {
        try self.codegen.emit("(");
        try genExpr(self.codegen, expr);
        try self.codegen.emit(")");
    }

    /// Emit expression only wrapped if it produces a block expression
    /// Block expressions (subscript, list, call, etc.) need parens for member access
    pub fn wrapIfBlock(self: *ExprEmitter, expr: ast.Node) CodegenError!void {
        if (producesBlockExpression(expr)) {
            try self.wrap(expr);
        } else {
            try genExpr(self.codegen, expr);
        }
    }

    /// Emit expression wrapped for numeric literal method calls
    /// Numeric literals need parens: (1).__round__() not 1.__round__()
    pub fn wrapIfNumericLiteral(self: *ExprEmitter, expr: ast.Node) CodegenError!void {
        const needs_parens = expr == .constant and
            (expr.constant.value == .int or expr.constant.value == .float);
        if (needs_parens) {
            try self.wrap(expr);
        } else {
            try genExpr(self.codegen, expr);
        }
    }

    /// Start a catch-wrapped expression for method chaining
    /// Pattern: (( - must be completed with endCatch()
    /// This ensures .method() binds to the result, not the handler
    pub fn startCatch(self: *ExprEmitter) CodegenError!void {
        try self.codegen.emit("((");
    }

    /// Complete the catch expression started with startCatch()
    /// Emits: ) catch handler)
    pub fn endCatch(self: *ExprEmitter, comptime handler: []const u8) CodegenError!void {
        try self.codegen.emit(") catch ");
        try self.codegen.emit(handler);
        try self.codegen.emit(")");
    }

    /// Emit a full expression with catch handler (convenience method)
    /// Emits: ((expr) catch handler)
    pub fn emitWithCatch(self: *ExprEmitter, expr: ast.Node, comptime handler: []const u8) CodegenError!void {
        try self.codegen.emit("((");
        try genExpr(self.codegen, expr);
        try self.codegen.emit(") catch ");
        try self.codegen.emit(handler);
        try self.codegen.emit(")");
    }

    /// Create a labeled block with a temp variable for the expression
    /// Use when you need to evaluate an expression once and use it multiple times
    /// Pattern: label_N: { const temp = expr; break :label_N result; }
    pub fn labeledBlock(
        self: *ExprEmitter,
        comptime prefix: []const u8,
        comptime temp_var: []const u8,
        expr: ast.Node,
    ) CodegenError!LabeledBlock {
        const label_id = self.codegen.block_label_counter;
        self.codegen.block_label_counter += 1;

        // Emit block start with temp variable
        try self.codegen.emitFmt("({s}_{d}: {{ const {s} = ", .{ prefix, label_id, temp_var });
        try genExpr(self.codegen, expr);
        try self.codegen.emit("; ");

        return LabeledBlock{
            .emitter = self,
            .label_id = label_id,
            .prefix = prefix,
        };
    }

    /// Create a labeled block without a temp variable
    /// Use when you just need a block scope for complex expressions
    pub fn labeledBlockRaw(
        self: *ExprEmitter,
        comptime prefix: []const u8,
    ) CodegenError!LabeledBlock {
        const label_id = self.codegen.block_label_counter;
        self.codegen.block_label_counter += 1;

        try self.codegen.emitFmt("({s}_{d}: {{ ", .{ prefix, label_id });

        return LabeledBlock{
            .emitter = self,
            .label_id = label_id,
            .prefix = prefix,
        };
    }

    /// Emit code wrapped with OOM catch handler using callback
    /// Pattern: ((inner)) catch @panic("OOM"))
    /// The double paren ensures proper catch precedence for method chaining
    /// Callback receives codegen to emit the inner expression
    pub fn withOOMCatch(
        self: *ExprEmitter,
        ctx: anytype,
        comptime emitInner: fn(@TypeOf(ctx), *NativeCodegen) CodegenError!void,
    ) CodegenError!void {
        try self.codegen.emit("((");
        try emitInner(ctx, self.codegen);
        try self.codegen.emit(")) catch @panic(\"OOM\"))");
    }

    /// Emit code wrapped with custom catch handler using callback
    /// Pattern: ((inner) catch handler)
    pub fn withCatch(
        self: *ExprEmitter,
        comptime handler: []const u8,
        ctx: anytype,
        comptime emitInner: fn(@TypeOf(ctx), *NativeCodegen) CodegenError!void,
    ) CodegenError!void {
        try self.codegen.emit("((");
        try emitInner(ctx, self.codegen);
        try self.codegen.emit(") catch ");
        try self.codegen.emit(handler);
        try self.codegen.emit(")");
    }

    /// Emit a labeled block with callback pattern (auto-closes)
    /// Pattern: (prefix_N: { const temp = expr; callback emits break; })
    pub fn withLabeledBlock(
        self: *ExprEmitter,
        comptime prefix: []const u8,
        comptime temp_var: []const u8,
        expr: ast.Node,
        ctx: anytype,
        comptime emitBreak: fn(@TypeOf(ctx), *LabeledBlock) CodegenError!void,
    ) CodegenError!void {
        var block = try self.labeledBlock(prefix, temp_var, expr);
        try emitBreak(ctx, &block);
        try block.close();
    }

    /// Emit a labeled block without temp var using callback (auto-closes)
    /// Pattern: (prefix_N: { callback emits content and break; })
    pub fn withLabeledBlockRaw(
        self: *ExprEmitter,
        comptime prefix: []const u8,
        ctx: anytype,
        comptime emitContent: fn(@TypeOf(ctx), *LabeledBlock) CodegenError!void,
    ) CodegenError!void {
        var block = try self.labeledBlockRaw(prefix);
        try emitContent(ctx, &block);
        try block.closeRaw();
    }
};

/// A labeled block that must be closed
pub const LabeledBlock = struct {
    emitter: *ExprEmitter,
    label_id: usize,
    prefix: []const u8,

    /// Emit a break with a formatted value
    pub fn breakWithFmt(self: *LabeledBlock, comptime fmt: []const u8, args: anytype) CodegenError!void {
        try self.emitter.codegen.emitFmt("break :{s}_{d} ", .{ self.prefix, self.label_id });
        try self.emitter.codegen.emitFmt(fmt, args);
    }

    /// Emit a break with an expression
    pub fn breakWithExpr(self: *LabeledBlock, expr: ast.Node) CodegenError!void {
        try self.emitter.codegen.emitFmt("break :{s}_{d} ", .{ self.prefix, self.label_id });
        try genExpr(self.emitter.codegen, expr);
    }

    /// Emit a break with a raw string value
    pub fn breakWith(self: *LabeledBlock, value: []const u8) CodegenError!void {
        try self.emitter.codegen.emitFmt("break :{s}_{d} {s}", .{ self.prefix, self.label_id, value });
    }

    /// Emit code inside the block (before break)
    pub fn emit(self: *LabeledBlock, s: []const u8) CodegenError!void {
        try self.emitter.codegen.emit(s);
    }

    /// Emit formatted code inside the block
    pub fn emitFmt(self: *LabeledBlock, comptime fmt: []const u8, args: anytype) CodegenError!void {
        try self.emitter.codegen.emitFmt(fmt, args);
    }

    /// Close the labeled block
    /// Must be called to complete the block
    pub fn close(self: *LabeledBlock) CodegenError!void {
        try self.emitter.codegen.emit("; })");
    }

    /// Close with just the block end (no semicolon before)
    pub fn closeRaw(self: *LabeledBlock) CodegenError!void {
        try self.emitter.codegen.emit(" })");
    }
};

// =============================================================================
// Convenience functions for common patterns
// =============================================================================

/// Check if expression needs parentheses for method calls
pub fn needsParensForMethodCall(expr: ast.Node) bool {
    return expr == .constant and
        (expr.constant.value == .int or expr.constant.value == .float);
}

/// Check if expression needs to be wrapped in a labeled block
/// Block expressions can't be directly subscripted or have methods called
pub fn needsLabeledBlock(expr: ast.Node) bool {
    return producesBlockExpression(expr);
}

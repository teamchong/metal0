/// ast_unparse - AST to Source Code
/// Mirrors cpython/Python/ast_unparse.c
///
/// Limited unparser for converting AST back to string representation,
/// primarily used for annotations during compilation.

const std = @import("std");

// ============================================================================
// Submodules
// ============================================================================

pub const types = @import("ast_unparse/types.zig");
pub const operators = @import("ast_unparse/operators.zig");
pub const core = @import("ast_unparse/core.zig");
const expressions = @import("ast_unparse/expressions.zig");

// ============================================================================
// Re-exports
// ============================================================================

// Types
pub const Precedence = types.Precedence;
pub const ExprKind = types.ExprKind;
pub const Keyword = types.Keyword;
pub const ConstantValue = types.ConstantValue;

// Operators
pub const BinaryOp = operators.BinaryOp;
pub const UnaryOp = operators.UnaryOp;
pub const CmpOp = operators.CmpOp;
pub const BoolOp = operators.BoolOp;

// Core Unparser
pub const Unparser = core.Unparser;

// ============================================================================
// Extended Unparser with Expression Methods
// ============================================================================

/// Extended Unparser with all expression methods
pub const UnparserExt = struct {
    unparser: Unparser,

    pub fn init(allocator: std.mem.Allocator) UnparserExt {
        return .{ .unparser = Unparser.init(allocator) };
    }

    pub fn deinit(self: *UnparserExt) void {
        self.unparser.deinit();
    }

    pub fn reset(self: *UnparserExt) void {
        self.unparser.reset();
    }

    pub fn getResult(self: *const UnparserExt) []const u8 {
        return self.unparser.getResult();
    }

    // Core methods
    pub fn appendChar(self: *UnparserExt, ch: u8) !void {
        try self.unparser.appendChar(ch);
    }

    pub fn appendStr(self: *UnparserExt, str: []const u8) !void {
        try self.unparser.appendStr(str);
    }

    pub fn appendInt(self: *UnparserExt, value: i64) !void {
        try self.unparser.appendInt(value);
    }

    pub fn appendFloat(self: *UnparserExt, value: f64) !void {
        try self.unparser.appendFloat(value);
    }

    pub fn appendRepr(self: *UnparserExt, str: []const u8) !void {
        try self.unparser.appendRepr(str);
    }

    pub fn unparseConstant(self: *UnparserExt, value: ConstantValue) !void {
        try self.unparser.unparseConstant(value);
    }

    pub fn unparseName(self: *UnparserExt, name: []const u8) !void {
        try self.unparser.unparseName(name);
    }

    // Operator expression methods
    pub fn unparseBinaryOp(self: *UnparserExt, op: BinaryOp, left: []const u8, right: []const u8, level: Precedence) !void {
        try expressions.unparseBinaryOp(&self.unparser, op, left, right, level);
    }

    pub fn unparseUnaryOp(self: *UnparserExt, op: UnaryOp, operand: []const u8) !void {
        try expressions.unparseUnaryOp(&self.unparser, op, operand);
    }

    pub fn unparseComparison(self: *UnparserExt, ops: []const CmpOp, comparators: []const []const u8) !void {
        try expressions.unparseComparison(&self.unparser, ops, comparators);
    }

    pub fn unparseBoolOp(self: *UnparserExt, op: BoolOp, values: []const []const u8, level: Precedence) !void {
        try expressions.unparseBoolOp(&self.unparser, op, values, level);
    }

    // Container expression methods
    pub fn unparseList(self: *UnparserExt, elements: []const []const u8) !void {
        try expressions.unparseList(&self.unparser, elements);
    }

    pub fn unparseTuple(self: *UnparserExt, elements: []const []const u8) !void {
        try expressions.unparseTuple(&self.unparser, elements);
    }

    pub fn unparseSet(self: *UnparserExt, elements: []const []const u8) !void {
        try expressions.unparseSet(&self.unparser, elements);
    }

    pub fn unparseDict(self: *UnparserExt, keys: []const ?[]const u8, values: []const []const u8) !void {
        try expressions.unparseDict(&self.unparser, keys, values);
    }

    // Access expression methods
    pub fn unparseAttribute(self: *UnparserExt, value: []const u8, attr: []const u8) !void {
        try expressions.unparseAttribute(&self.unparser, value, attr);
    }

    pub fn unparseSubscript(self: *UnparserExt, value: []const u8, slice: []const u8) !void {
        try expressions.unparseSubscript(&self.unparser, value, slice);
    }

    pub fn unparseSlice(self: *UnparserExt, lower: ?[]const u8, upper: ?[]const u8, step: ?[]const u8) !void {
        try expressions.unparseSlice(&self.unparser, lower, upper, step);
    }

    // Call and control flow expression methods
    pub fn unparseCall(self: *UnparserExt, func: []const u8, args: []const []const u8, keywords: []const Keyword) !void {
        try expressions.unparseCall(&self.unparser, func, args, keywords);
    }

    pub fn unparseIfExp(self: *UnparserExt, test_expr: []const u8, body: []const u8, else_body: []const u8, level: Precedence) !void {
        try expressions.unparseIfExp(&self.unparser, test_expr, body, else_body, level);
    }

    pub fn unparseLambda(self: *UnparserExt, args: []const u8, body: []const u8, level: Precedence) !void {
        try expressions.unparseLambda(&self.unparser, args, body, level);
    }

    // Special expression methods
    pub fn unparseStarred(self: *UnparserExt, value: []const u8) !void {
        try expressions.unparseStarred(&self.unparser, value);
    }

    pub fn unparseNamedExpr(self: *UnparserExt, target: []const u8, value: []const u8) !void {
        try expressions.unparseNamedExpr(&self.unparser, target, value);
    }

    pub fn unparseAwait(self: *UnparserExt, value: []const u8) !void {
        try expressions.unparseAwait(&self.unparser, value);
    }

    pub fn unparseYield(self: *UnparserExt, value: ?[]const u8) !void {
        try expressions.unparseYield(&self.unparser, value);
    }

    pub fn unparseYieldFrom(self: *UnparserExt, value: []const u8) !void {
        try expressions.unparseYieldFrom(&self.unparser, value);
    }
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the ast_unparse module
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

test "unparse constant" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseConstant(.none);
    try std.testing.expectEqualStrings("None", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.{ .int_val = 42 });
    try std.testing.expectEqualStrings("42", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.true_val);
    try std.testing.expectEqualStrings("True", unparser.getResult());
}

test "unparse string repr" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseConstant(.{ .str_val = "hello" });
    try std.testing.expectEqualStrings("'hello'", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.{ .str_val = "it's" });
    try std.testing.expectEqualStrings("'it\\'s'", unparser.getResult());
}

test "unparse list" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    const elements = [_][]const u8{ "1", "2", "3" };
    try unparser.unparseList(&elements);
    try std.testing.expectEqualStrings("[1, 2, 3]", unparser.getResult());
}

test "unparse tuple" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    const single = [_][]const u8{"1"};
    try unparser.unparseTuple(&single);
    try std.testing.expectEqualStrings("(1,)", unparser.getResult());

    unparser.reset();
    const multi = [_][]const u8{ "1", "2" };
    try unparser.unparseTuple(&multi);
    try std.testing.expectEqualStrings("(1, 2)", unparser.getResult());
}

test "unparse set" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    const empty = [_][]const u8{};
    try unparser.unparseSet(&empty);
    try std.testing.expectEqualStrings("set()", unparser.getResult());

    unparser.reset();
    const elements = [_][]const u8{ "1", "2" };
    try unparser.unparseSet(&elements);
    try std.testing.expectEqualStrings("{1, 2}", unparser.getResult());
}

test "unparse attribute" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    try unparser.unparseAttribute("obj", "attr");
    try std.testing.expectEqualStrings("obj.attr", unparser.getResult());
}

test "unparse subscript" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    try unparser.unparseSubscript("lst", "0");
    try std.testing.expectEqualStrings("lst[0]", unparser.getResult());
}

test "unparse slice" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    try unparser.unparseSlice("1", "10", "2");
    try std.testing.expectEqualStrings("1:10:2", unparser.getResult());

    unparser.reset();
    try unparser.unparseSlice(null, "10", null);
    try std.testing.expectEqualStrings(":10", unparser.getResult());
}

test "unparse call" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    const args = [_][]const u8{ "1", "2" };
    const keywords = [_]Keyword{.{ .name = "x", .value = "3" }};
    try unparser.unparseCall("func", &args, &keywords);
    try std.testing.expectEqualStrings("func(1, 2, x=3)", unparser.getResult());
}

test "unparse if expression" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    try unparser.unparseIfExp("cond", "a", "b", .PR_TUPLE);
    try std.testing.expectEqualStrings("a if cond else b", unparser.getResult());
}

test "unparse walrus operator" {
    const allocator = std.testing.allocator;

    var unparser = UnparserExt.init(allocator);
    defer unparser.deinit();

    try unparser.unparseNamedExpr("x", "10");
    try std.testing.expectEqualStrings("(x := 10)", unparser.getResult());
}

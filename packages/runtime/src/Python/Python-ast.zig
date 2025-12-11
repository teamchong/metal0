/// Python-ast - AST Node Types
/// Mirrors cpython/Python/Python-ast.c (auto-generated from Parser/Python.asdl)
///
/// Defines all AST node types for the Python abstract syntax tree.
/// This is the canonical representation of parsed Python code.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Re-export all submodules
pub const module_types = @import("Python-ast/module_types.zig");
pub const statement_types = @import("Python-ast/statement_types.zig");
pub const expression_types = @import("Python-ast/expression_types.zig");
pub const operator_types = @import("Python-ast/operator_types.zig");
pub const supporting_types = @import("Python-ast/supporting_types.zig");
pub const pattern_types = @import("Python-ast/pattern_types.zig");
pub const constant_types = @import("Python-ast/constant_types.zig");
pub const visitor = @import("Python-ast/visitor.zig");
const init_module = @import("Python-ast/init.zig");

// ============================================================================
// Re-export all types for backward compatibility
// ============================================================================

// Module types
pub const ModKind = module_types.ModKind;
pub const Module = module_types.Module;

// Statement types
pub const StmtKind = statement_types.StmtKind;
pub const Statement = statement_types.Statement;
pub const StmtData = statement_types.StmtData;
pub const FunctionDefData = statement_types.FunctionDefData;
pub const ClassDefData = statement_types.ClassDefData;
pub const ReturnData = statement_types.ReturnData;
pub const DeleteData = statement_types.DeleteData;
pub const AssignData = statement_types.AssignData;
pub const TypeAliasData = statement_types.TypeAliasData;
pub const AugAssignData = statement_types.AugAssignData;
pub const AnnAssignData = statement_types.AnnAssignData;
pub const ForData = statement_types.ForData;
pub const WhileData = statement_types.WhileData;
pub const IfData = statement_types.IfData;
pub const WithData = statement_types.WithData;
pub const MatchData = statement_types.MatchData;
pub const RaiseData = statement_types.RaiseData;
pub const TryData = statement_types.TryData;
pub const AssertData = statement_types.AssertData;
pub const ImportData = statement_types.ImportData;
pub const ImportFromData = statement_types.ImportFromData;
pub const GlobalData = statement_types.GlobalData;
pub const NonlocalData = statement_types.NonlocalData;
pub const ExprData = statement_types.ExprData;

// Expression types
pub const ExprKind = expression_types.ExprKind;
pub const Expr = expression_types.Expr;
pub const ExprContext = expression_types.ExprContext;

// Operator types
pub const Operator = operator_types.Operator;
pub const UnaryOp = operator_types.UnaryOp;
pub const BoolOp = operator_types.BoolOp;
pub const CmpOp = operator_types.CmpOp;

// Supporting types
pub const Arguments = supporting_types.Arguments;
pub const Arg = supporting_types.Arg;
pub const Keyword = supporting_types.Keyword;
pub const Alias = supporting_types.Alias;
pub const WithItem = supporting_types.WithItem;
pub const MatchCase = supporting_types.MatchCase;
pub const ExceptHandler = supporting_types.ExceptHandler;
pub const TypeIgnore = supporting_types.TypeIgnore;
pub const TypeParam = supporting_types.TypeParam;
pub const TypeParamKind = supporting_types.TypeParamKind;

// Pattern types
pub const PatternKind = pattern_types.PatternKind;
pub const Pattern = pattern_types.Pattern;

// Constant types
pub const Constant = constant_types.Constant;

// Visitor
pub const Visitor = visitor.Visitor;

// Initialization
pub const init = init_module.init;
pub const reset = init_module.reset;

// ============================================================================
// Tests
// ============================================================================

test "statement kind" {
    try std.testing.expectEqual(StmtKind.FunctionDef, StmtKind.FunctionDef);
    try std.testing.expectEqual(StmtKind.Pass, StmtKind.Pass);
}

test "expression kind" {
    try std.testing.expectEqual(ExprKind.Constant, ExprKind.Constant);
    try std.testing.expectEqual(ExprKind.Name, ExprKind.Name);
}

test "operator types" {
    try std.testing.expectEqual(Operator.Add, Operator.Add);
    try std.testing.expectEqual(CmpOp.Eq, CmpOp.Eq);
}

test "constant types" {
    const c1 = Constant{ .int_val = 42 };
    try std.testing.expectEqual(@as(i64, 42), c1.int_val);

    const c2 = Constant.none;
    _ = c2;

    const c3 = Constant{ .str_val = "hello" };
    try std.testing.expectEqualStrings("hello", c3.str_val);
}

test "expression context" {
    try std.testing.expectEqual(ExprContext.Load, ExprContext.Load);
    try std.testing.expectEqual(ExprContext.Store, ExprContext.Store);
    try std.testing.expectEqual(ExprContext.Del, ExprContext.Del);
}

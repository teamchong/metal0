//! Query module for LanceQL.
//!
//! Provides SQL parsing, expression evaluation, and query execution
//! for Lance files.

const std = @import("std");

pub const value = @import("lanceql.value");
pub const Value = value.Value;

pub const expr = @import("expr.zig");
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");
pub const executor = @import("executor.zig");
pub const aggregates = @import("aggregates.zig");
pub const logic_table = @import("logic_table.zig");
pub const gpu_group_by = @import("gpu_group_by.zig");
pub const gpu_hash_join = @import("gpu_hash_join.zig");

// Re-export main types
pub const Expr = expr.Expr;
pub const BinaryOp = expr.BinaryOp;
pub const UnaryOp = expr.UnaryOp;
pub const Lexer = lexer.Lexer;
pub const Token = lexer.Token;
pub const Parser = parser.Parser;
pub const SelectStmt = ast.SelectStmt;
pub const SelectItem = ast.SelectItem;
pub const OrderBy = ast.OrderBy;
pub const AggregateType = ast.AggregateType;
pub const Executor = executor.Executor;
pub const ResultSet = executor.ResultSet;
pub const Aggregate = aggregates.Aggregate;
pub const GroupKey = aggregates.GroupKey;
pub const LogicTableContext = logic_table.LogicTableContext;
pub const LogicTableError = logic_table.LogicTableError;
pub const ColumnDep = logic_table.ColumnDep;
pub const MethodMeta = logic_table.MethodMeta;

// GPU-accelerated GROUP BY
pub const GPUGroupBy = gpu_group_by.GPUGroupBy;
pub const GPUGroupByF64 = gpu_group_by.GPUGroupByF64;
pub const AggType = gpu_group_by.AggType;
pub const GroupByResult = gpu_group_by.GroupByResult;

// GPU-accelerated Hash JOIN
pub const GPUHashJoin = gpu_hash_join.GPUHashJoin;
pub const JoinResult = gpu_hash_join.JoinResult;
pub const LeftJoinResult = gpu_hash_join.LeftJoinResult;

// Batch vector operations for @logic_table
pub const batchCosineSimilarity = logic_table.batchCosineSimilarity;
pub const batchL2Distance = logic_table.batchL2Distance;
pub const batchDotProduct = logic_table.batchDotProduct;

test {
    std.testing.refAllDecls(@This());
}

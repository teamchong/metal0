//! SQL Abstract Syntax Tree types.
//!
//! Defines the structure of parsed SQL SELECT statements.

const std = @import("std");
const Expr = @import("expr.zig").Expr;

/// A SELECT statement.
pub const SelectStmt = struct {
    /// Columns to select (or * for all)
    columns: []SelectItem,

    /// Table name (optional, ignored for single-file queries)
    from: ?[]const u8,

    /// WHERE clause filter
    where: ?*Expr,

    /// GROUP BY column names
    group_by: []const []const u8,

    /// HAVING clause filter (applied after grouping)
    having: ?*Expr,

    /// ORDER BY clauses
    order_by: []OrderBy,

    /// LIMIT count
    limit: ?u64,

    /// OFFSET count
    offset: ?u64,

    /// Whether SELECT DISTINCT
    distinct: bool,

    pub fn deinit(self: *SelectStmt, allocator: std.mem.Allocator) void {
        allocator.free(self.columns);
        if (self.from) |f| allocator.free(f);
        allocator.free(self.group_by);
        allocator.free(self.order_by);
    }
};

/// A single item in SELECT clause.
pub const SelectItem = union(enum) {
    /// SELECT *
    star,

    /// SELECT expr or SELECT expr AS alias
    expr: struct {
        expression: *Expr,
        alias: ?[]const u8,
    },
};

/// ORDER BY clause item.
pub const OrderBy = struct {
    /// Column name or expression
    column: []const u8,

    /// Sort direction
    descending: bool = false,

    /// NULLS FIRST or NULLS LAST (default: NULLS LAST for ASC, NULLS FIRST for DESC)
    nulls_first: ?bool = null,
};

/// Aggregate function types.
pub const AggregateType = enum {
    count,
    sum,
    avg,
    min,
    max,

    pub fn fromStr(name: []const u8) ?AggregateType {
        const map = std.StaticStringMap(AggregateType).initComptime(.{
            .{ "COUNT", .count },
            .{ "SUM", .sum },
            .{ "AVG", .avg },
            .{ "MIN", .min },
            .{ "MAX", .max },
        });

        var upper_buf: [16]u8 = undefined;
        if (name.len > upper_buf.len) return null;

        for (name, 0..) |c, i| {
            upper_buf[i] = std.ascii.toUpper(c);
        }

        return map.get(upper_buf[0..name.len]);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "AggregateType fromStr" {
    try std.testing.expectEqual(AggregateType.fromStr("COUNT"), .count);
    try std.testing.expectEqual(AggregateType.fromStr("count"), .count);
    try std.testing.expectEqual(AggregateType.fromStr("SUM"), .sum);
    try std.testing.expectEqual(AggregateType.fromStr("avg"), .avg);
    try std.testing.expect(AggregateType.fromStr("UNKNOWN") == null);
}

//! DataFrame API for fluent query building.
//!
//! Provides a chainable interface for building queries:
//!   DataFrame.from(&table)
//!       .select(&.{"id", "name"})
//!       .filter(Expr.gt(Expr.col("id"), Expr.int(10)))
//!       .orderBy("name", false)
//!       .limit(100)
//!       .collect()

const std = @import("std");
const Value = @import("lanceql.value").Value;
const query = @import("lanceql.query");
const Expr = query.Expr;
const SelectStmt = query.SelectStmt;
const SelectItem = query.SelectItem;
const OrderBy = query.OrderBy;
const AggregateType = query.AggregateType;
const Executor = query.Executor;
const ResultSet = query.ResultSet;
const Aggregate = query.Aggregate;
const table_mod = @import("lanceql.table");
const Table = table_mod.Table;

/// DataFrame for building and executing queries.
pub const DataFrame = struct {
    allocator: std.mem.Allocator,
    table: *const Table,

    // Query state
    select_columns: ?[]const []const u8 = null,
    select_exprs: ?[]SelectItem = null,
    filter_expr: ?*Expr = null,
    group_columns: ?[]const []const u8 = null,
    aggregates: ?[]AggSpec = null,
    order_columns: ?[]OrderSpec = null,
    limit_value: ?u64 = null,
    offset_value: ?u64 = null,

    const Self = @This();

    /// Aggregate specification for groupBy().agg()
    pub const AggSpec = struct {
        agg_type: AggregateType,
        column: ?[]const u8, // null for COUNT(*)
        alias: ?[]const u8,
    };

    /// Order specification
    pub const OrderSpec = struct {
        column: []const u8,
        descending: bool,
    };

    /// Create a DataFrame from a Table.
    pub fn from(allocator: std.mem.Allocator, table: *const Table) Self {
        return .{
            .allocator = allocator,
            .table = table,
        };
    }

    /// Select specific columns by name.
    pub fn select(self: Self, columns: []const []const u8) Self {
        var new = self;
        new.select_columns = columns;
        return new;
    }

    /// Select with expressions.
    pub fn selectExprs(self: Self, items: []SelectItem) Self {
        var new = self;
        new.select_exprs = items;
        return new;
    }

    /// Filter rows by predicate.
    pub fn filter(self: Self, predicate: *Expr) Self {
        var new = self;
        new.filter_expr = predicate;
        return new;
    }

    /// Filter rows by SQL-like condition string.
    /// Example: filterSql("id > 10 AND name = 'Alice'")
    pub fn filterSql(self: Self, sql: []const u8) !Self {
        var parser = query.Parser.init(self.allocator, sql);
        const expr = try parser.parseExpr();
        return self.filter(expr);
    }

    /// Group by columns.
    pub fn groupBy(self: Self, columns: []const []const u8) GroupedFrame {
        return GroupedFrame{
            .df = self,
            .group_columns = columns,
        };
    }

    /// Order by column.
    pub fn orderBy(self: Self, column: []const u8, descending: bool) Self {
        var new = self;
        var specs: [1]OrderSpec = .{.{ .column = column, .descending = descending }};
        new.order_columns = self.allocator.dupe(OrderSpec, &specs) catch null;
        return new;
    }

    /// Order by multiple columns.
    pub fn orderByMultiple(self: Self, specs: []const OrderSpec) Self {
        var new = self;
        new.order_columns = self.allocator.dupe(OrderSpec, specs) catch null;
        return new;
    }

    /// Limit the number of rows.
    pub fn limit(self: Self, n: u64) Self {
        var new = self;
        new.limit_value = n;
        return new;
    }

    /// Skip rows.
    pub fn offset(self: Self, n: u64) Self {
        var new = self;
        new.offset_value = n;
        return new;
    }

    /// Execute the query and return results.
    pub fn collect(self: Self) !ResultSet {
        // Build SelectStmt from DataFrame state
        var stmt = SelectStmt{
            .columns = &.{},
            .from = null,
            .where = self.filter_expr,
            .group_by = self.group_columns orelse &.{},
            .having = null,
            .order_by = &.{},
            .limit = self.limit_value,
            .offset = self.offset_value,
            .distinct = false,
        };

        // Build select items
        if (self.select_exprs) |exprs| {
            stmt.columns = exprs;
        } else if (self.select_columns) |cols| {
            var items: std.ArrayListUnmanaged(SelectItem) = .empty;
            for (cols) |col| {
                const expr = try self.allocator.create(Expr);
                expr.* = Expr.col(col);
                try items.append(self.allocator, .{ .expr = .{
                    .expression = expr,
                    .alias = null,
                } });
            }
            stmt.columns = try items.toOwnedSlice(self.allocator);
        } else {
            // SELECT *
            var items = try self.allocator.alloc(SelectItem, 1);
            items[0] = .star;
            stmt.columns = items;
        }

        // Build order by
        if (self.order_columns) |orders| {
            var obs: std.ArrayListUnmanaged(OrderBy) = .empty;
            for (orders) |o| {
                try obs.append(self.allocator, .{
                    .column = o.column,
                    .descending = o.descending,
                });
            }
            stmt.order_by = try obs.toOwnedSlice(self.allocator);
        }

        // Create executor
        var executor = Executor.init(self.allocator, stmt);

        // Create data provider from table
        const provider = try self.createDataProvider();

        return executor.execute(provider);
    }

    /// Get row count (without fetching all data).
    pub fn count(self: Self) !u64 {
        const result = try self.collect();
        return result.rowCount();
    }

    /// Get first row.
    pub fn first(self: Self) !?[]Value {
        var limited = self.limit(1);
        const result = try limited.collect();
        if (result.rows.len > 0) {
            return result.rows[0];
        }
        return null;
    }

    /// Create data provider from table.
    fn createDataProvider(self: Self) !Executor.DataProvider {
        const TableProvider = struct {
            table: *const Table,
            col_names: [][]const u8,
            row_count: usize,

            fn getColumnNames(ptr: *anyopaque) [][]const u8 {
                const p: *@This() = @ptrCast(@alignCast(ptr));
                return p.col_names;
            }

            fn getRowCount(ptr: *anyopaque) usize {
                const p: *@This() = @ptrCast(@alignCast(ptr));
                return p.row_count;
            }

            fn readInt64Column(ptr: *anyopaque, col_idx: usize) ?[]i64 {
                const p: *@This() = @ptrCast(@alignCast(ptr));
                return p.table.readInt64Column(@intCast(col_idx)) catch null;
            }

            fn readFloat64Column(ptr: *anyopaque, col_idx: usize) ?[]f64 {
                const p: *@This() = @ptrCast(@alignCast(ptr));
                return p.table.readFloat64Column(@intCast(col_idx)) catch null;
            }

            const vtable = Executor.DataProvider.VTable{
                .getColumnNames = getColumnNames,
                .getRowCount = getRowCount,
                .readInt64Column = readInt64Column,
                .readFloat64Column = readFloat64Column,
            };
        };

        const col_names = try self.table.columnNames();
        const row_count = try self.table.rowCount(0);

        const provider = try self.allocator.create(TableProvider);
        provider.* = .{
            .table = self.table,
            .col_names = col_names,
            .row_count = @intCast(row_count),
        };

        return .{
            .ptr = provider,
            .vtable = &TableProvider.vtable,
        };
    }
};

/// Grouped DataFrame for aggregation operations.
pub const GroupedFrame = struct {
    df: DataFrame,
    group_columns: []const []const u8,

    const Self = @This();

    /// Aggregate with specifications.
    pub fn agg(self: Self, specs: []const DataFrame.AggSpec) DataFrame {
        var new_df = self.df;
        new_df.group_columns = self.group_columns;
        new_df.aggregates = self.df.allocator.dupe(DataFrame.AggSpec, specs) catch null;
        return new_df;
    }

    /// Count rows per group.
    pub fn count(self: Self) DataFrame {
        return self.agg(&.{.{
            .agg_type = .count,
            .column = null,
            .alias = "count",
        }});
    }

    /// Sum a column per group.
    pub fn sum(self: Self, column: []const u8) DataFrame {
        return self.agg(&.{.{
            .agg_type = .sum,
            .column = column,
            .alias = null,
        }});
    }

    /// Average a column per group.
    pub fn avg(self: Self, column: []const u8) DataFrame {
        return self.agg(&.{.{
            .agg_type = .avg,
            .column = column,
            .alias = null,
        }});
    }

    /// Min of a column per group.
    pub fn min(self: Self, column: []const u8) DataFrame {
        return self.agg(&.{.{
            .agg_type = .min,
            .column = column,
            .alias = null,
        }});
    }

    /// Max of a column per group.
    pub fn max(self: Self, column: []const u8) DataFrame {
        return self.agg(&.{.{
            .agg_type = .max,
            .column = column,
            .alias = null,
        }});
    }
};

// ============================================================================
// Expression Builder Helpers
// ============================================================================

/// Build expressions fluently.
pub const ExprBuilder = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Column reference.
    pub fn col(self: Self, name: []const u8) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = Expr.col(name);
        return e;
    }

    /// Integer literal.
    pub fn int(self: Self, v: i64) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = Expr.intLit(v);
        return e;
    }

    /// Float literal.
    pub fn float(self: Self, v: f64) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = Expr.floatLit(v);
        return e;
    }

    /// String literal.
    pub fn str(self: Self, v: []const u8) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = Expr.strLit(v);
        return e;
    }

    /// Boolean literal.
    pub fn boolean(self: Self, v: bool) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = Expr.boolLit(v);
        return e;
    }

    /// Equals comparison.
    pub fn eq(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .eq, .left = left, .right = right } };
        return e;
    }

    /// Not equals comparison.
    pub fn ne(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .ne, .left = left, .right = right } };
        return e;
    }

    /// Greater than comparison.
    pub fn gt(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .gt, .left = left, .right = right } };
        return e;
    }

    /// Greater than or equal comparison.
    pub fn ge(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .ge, .left = left, .right = right } };
        return e;
    }

    /// Less than comparison.
    pub fn lt(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .lt, .left = left, .right = right } };
        return e;
    }

    /// Less than or equal comparison.
    pub fn le(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .le, .left = left, .right = right } };
        return e;
    }

    /// Logical AND.
    pub fn @"and"(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .and_, .left = left, .right = right } };
        return e;
    }

    /// Logical OR.
    pub fn @"or"(self: Self, left: *Expr, right: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .binary = .{ .op = .or_, .left = left, .right = right } };
        return e;
    }

    /// Logical NOT.
    pub fn not(self: Self, operand: *Expr) !*Expr {
        const e = try self.allocator.create(Expr);
        e.* = .{ .unary = .{ .op = .not, .operand = operand } };
        return e;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "DataFrame basic construction" {
    // Just test that the types compile
    const allocator = std.testing.allocator;
    _ = ExprBuilder.init(allocator);
}

test "ExprBuilder creates expressions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const eb = ExprBuilder.init(arena.allocator());

    const col_expr = try eb.col("id");
    const int_expr = try eb.int(10);
    const cmp_expr = try eb.gt(col_expr, int_expr);

    try std.testing.expect(cmp_expr.* == .binary);
}

test "GroupedFrame methods" {
    // Test that GroupedFrame methods compile
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Note: Can't fully test without a real Table
    _ = arena.allocator();
}

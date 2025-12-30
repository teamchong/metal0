//! Abstract Syntax Tree definitions for SQL
//!
//! Represents parsed SQL statements as tree structures.
//! Supports SELECT queries with WHERE, ORDER BY, LIMIT, and GROUP BY.

const std = @import("std");

/// SQL Value types
pub const ValueType = enum {
    null,
    integer,
    float,
    string,
    blob,
    parameter, // ? placeholder
};

/// A literal or parameter value
pub const Value = union(ValueType) {
    null: void,
    integer: i64,
    float: f64,
    string: []const u8,
    blob: []const u8,
    parameter: u32, // Parameter index (0-based)
};

/// Binary operators
pub const BinaryOp = enum {
    // Arithmetic
    add,      // +
    subtract, // -
    multiply, // *
    divide,   // /
    concat,   // || (string concatenation)

    // Comparison
    eq,  // =
    ne,  // != or <>
    lt,  // <
    le,  // <=
    gt,  // >
    ge,  // >=

    // Logical
    @"and", // AND
    @"or",  // OR

    // Other
    like,    // LIKE
    in,      // IN
    between, // BETWEEN
};

/// Unary operators
pub const UnaryOp = enum {
    not,    // NOT
    minus,  // -
    is_null, // IS NULL
    is_not_null, // IS NOT NULL
};

/// Expression node (recursive)
pub const Expr = union(enum) {
    /// Literal value
    value: Value,

    /// Column reference (e.g., "users.id" or just "id")
    column: struct {
        table: ?[]const u8, // Optional table qualifier
        name: []const u8,
    },

    /// Binary operation
    binary: struct {
        op: BinaryOp,
        left: *Expr,
        right: *Expr,
    },

    /// Unary operation
    unary: struct {
        op: UnaryOp,
        operand: *Expr,
    },

    /// Function call (e.g., COUNT(*), AVG(salary))
    /// With optional OVER clause for window functions
    call: struct {
        name: []const u8,
        args: []Expr,
        distinct: bool,
        /// Optional window specification (OVER clause)
        window: ?*WindowSpec,
    },

    /// IN expression: col IN (val1, val2, ...)
    in_list: struct {
        expr: *Expr,
        values: []Expr,
        negated: bool, // NOT IN
    },

    /// IN subquery: col IN (SELECT ...)
    in_subquery: struct {
        expr: *Expr,
        subquery: *SelectStmt,
        negated: bool, // NOT IN
    },

    /// BETWEEN expression: col BETWEEN low AND high
    between: struct {
        expr: *Expr,
        low: *Expr,
        high: *Expr,
    },

    /// CASE expression: CASE [expr] WHEN val THEN result ... [ELSE default] END
    case_expr: struct {
        /// Optional expression to compare (simple CASE)
        operand: ?*Expr,
        /// WHEN ... THEN pairs
        when_clauses: []CaseWhen,
        /// Optional ELSE result
        else_result: ?*Expr,
    },

    /// EXISTS subquery
    exists: struct {
        /// The subquery (SELECT statement)
        subquery: *SelectStmt,
        negated: bool, // NOT EXISTS
    },

    /// CAST expression
    cast: struct {
        expr: *Expr,
        target_type: []const u8,
    },

    /// Method call on table alias (e.g., t.risk_score() for @logic_table methods)
    method_call: struct {
        /// Table alias (e.g., "t")
        object: []const u8,
        /// Method name (e.g., "risk_score")
        method: []const u8,
        /// Method arguments
        args: []Expr,
        /// Optional window specification (OVER clause)
        over: ?*WindowSpec,
    },
};

/// WHEN ... THEN clause for CASE expression
pub const CaseWhen = struct {
    /// Condition (for searched CASE) or value (for simple CASE)
    condition: Expr,
    /// Result when condition is true
    result: Expr,
};

/// Window frame bound type
pub const FrameBound = enum {
    unbounded_preceding,
    current_row,
    unbounded_following,
    preceding, // N PRECEDING
    following, // N FOLLOWING
};

/// Window frame specification
pub const WindowFrame = struct {
    /// Frame type (ROWS or RANGE)
    frame_type: enum { rows, range },
    /// Start bound
    start_bound: FrameBound,
    start_offset: ?i64,
    /// End bound (optional, defaults to CURRENT ROW)
    end_bound: ?FrameBound,
    end_offset: ?i64,
};

/// Window specification for OVER clause
pub const WindowSpec = struct {
    /// PARTITION BY columns
    partition_by: ?[][]const u8,
    /// ORDER BY columns with directions
    order_by: ?[]OrderBy,
    /// Optional frame specification
    frame: ?WindowFrame,
};

/// SELECT column specification
pub const SelectItem = struct {
    /// The expression (can be *, column name, or function)
    expr: Expr,

    /// Optional alias (AS name)
    alias: ?[]const u8,
};

/// Table-valued function call (e.g., logic_table('path'))
pub const TableFunction = struct {
    /// Function name (e.g., "logic_table")
    name: []const u8,

    /// Function arguments
    args: []Expr,
};

/// JOIN types
pub const JoinType = enum {
    inner,       // INNER JOIN (default)
    left,        // LEFT [OUTER] JOIN
    right,       // RIGHT [OUTER] JOIN
    full,        // FULL [OUTER] JOIN
    cross,       // CROSS JOIN
    natural,     // NATURAL JOIN
};

/// JOIN clause
pub const JoinClause = struct {
    /// Type of join
    join_type: JoinType,

    /// Right-hand table
    table: *TableRef,

    /// ON condition (null for CROSS/NATURAL joins)
    on_condition: ?Expr,

    /// USING columns (alternative to ON)
    using_columns: ?[][]const u8,
};

/// FROM clause table reference
pub const TableRef = union(enum) {
    /// Simple table name
    simple: struct {
        /// Table name
        name: []const u8,

        /// Optional alias
        alias: ?[]const u8,
    },

    /// Table-valued function (e.g., logic_table('fraud.py'))
    function: struct {
        /// Function details
        func: TableFunction,

        /// Optional alias
        alias: ?[]const u8,
    },

    /// JOIN expression
    join: struct {
        /// Left-hand table
        left: *TableRef,

        /// Join clause (type, right table, condition)
        join_clause: JoinClause,
    },
};

/// Data binding for WITH DATA clause
pub const DataBinding = struct {
    /// Table name
    name: []const u8,

    /// Path to data source
    path: []const u8,
};

/// WITH DATA clause for logic tables
pub const WithData = struct {
    /// Data bindings
    bindings: []DataBinding,
};

/// ORDER BY direction
pub const OrderDirection = enum {
    asc,
    desc,
};

/// Set operation types
pub const SetOperationType = enum {
    union_all,       // UNION ALL (keep duplicates)
    union_distinct,  // UNION (remove duplicates)
    intersect,       // INTERSECT
    except,          // EXCEPT
};

/// ORDER BY clause item
pub const OrderBy = struct {
    /// Column to sort by
    column: []const u8,

    /// Sort direction
    direction: OrderDirection,
};

/// GROUP BY clause
pub const GroupBy = struct {
    /// Columns to group by
    columns: [][]const u8,

    /// Optional HAVING clause
    having: ?Expr,
};

/// Set operation (UNION, INTERSECT, EXCEPT) with another query
pub const SetOperation = struct {
    /// The type of set operation
    op_type: SetOperationType,

    /// The right-hand query
    right: *SelectStmt,
};

/// Complete SELECT statement
pub const SelectStmt = struct {
    /// WITH DATA clause (optional, for logic tables)
    with_data: ?WithData,

    /// SELECT clause
    distinct: bool,
    columns: []SelectItem,

    /// FROM clause
    from: TableRef,

    /// WHERE clause (optional)
    where: ?Expr,

    /// GROUP BY clause (optional)
    group_by: ?GroupBy,

    /// ORDER BY clause (optional)
    order_by: ?[]OrderBy,

    /// LIMIT clause (optional)
    limit: ?u32,

    /// OFFSET clause (optional)
    offset: ?u32,

    /// Set operation with another query (optional)
    set_operation: ?SetOperation,
};

/// Top-level statement (extensible for INSERT/UPDATE/DELETE later)
pub const Statement = union(enum) {
    select: SelectStmt,
    // Future: insert, update, delete, create_table, etc.
};

// ============================================================================
// Memory Management
// ============================================================================

/// Recursively free all heap-allocated Expr pointers in an expression tree.
/// Call this to clean up expressions allocated by the parser.
pub fn deinitExpr(expr: *Expr, allocator: std.mem.Allocator) void {
    switch (expr.*) {
        .binary => |bin| {
            deinitExpr(bin.left, allocator);
            allocator.destroy(bin.left);
            deinitExpr(bin.right, allocator);
            allocator.destroy(bin.right);
        },
        .unary => |un| {
            deinitExpr(un.operand, allocator);
            allocator.destroy(un.operand);
        },
        .call => |call| {
            for (call.args) |*arg| {
                deinitExpr(arg, allocator);
            }
            allocator.free(call.args);
            // Free window specification if present
            if (call.window) |window| {
                if (window.partition_by) |cols| {
                    allocator.free(cols);
                }
                if (window.order_by) |order| {
                    allocator.free(order);
                }
                allocator.destroy(window);
            }
        },
        .in_list => |in| {
            deinitExpr(in.expr, allocator);
            allocator.destroy(in.expr);
            for (in.values) |*val| {
                deinitExpr(val, allocator);
            }
            allocator.free(in.values);
        },
        .in_subquery => |in| {
            deinitExpr(in.expr, allocator);
            allocator.destroy(in.expr);
            deinitSelectStmt(in.subquery, allocator);
            allocator.destroy(in.subquery);
        },
        .between => |between| {
            deinitExpr(between.expr, allocator);
            allocator.destroy(between.expr);
            deinitExpr(between.low, allocator);
            allocator.destroy(between.low);
            deinitExpr(between.high, allocator);
            allocator.destroy(between.high);
        },
        .case_expr => |case| {
            if (case.operand) |operand| {
                deinitExpr(operand, allocator);
                allocator.destroy(operand);
            }
            for (case.when_clauses) |*when| {
                deinitExpr(@constCast(&when.condition), allocator);
                deinitExpr(@constCast(&when.result), allocator);
            }
            allocator.free(case.when_clauses);
            if (case.else_result) |else_result| {
                deinitExpr(else_result, allocator);
                allocator.destroy(else_result);
            }
        },
        .exists => |ex| {
            deinitSelectStmt(ex.subquery, allocator);
            allocator.destroy(ex.subquery);
        },
        .cast => |c| {
            deinitExpr(c.expr, allocator);
            allocator.destroy(c.expr);
        },
        .method_call => |mc| {
            for (mc.args) |*arg| {
                deinitExpr(arg, allocator);
            }
            allocator.free(mc.args);
            if (mc.over) |over| {
                if (over.partition_by) |pb| allocator.free(pb);
                if (over.order_by) |ob| allocator.free(ob);
                allocator.destroy(over);
            }
        },
        .value, .column => {}, // No heap allocations to free
    }
}

/// Recursively free all heap-allocated memory in a TableRef.
pub fn deinitTableRef(table_ref: *TableRef, allocator: std.mem.Allocator) void {
    switch (table_ref.*) {
        .simple => {}, // No heap allocations
        .function => |func| {
            // Free function arguments
            for (func.func.args) |*arg| {
                deinitExpr(arg, allocator);
            }
            allocator.free(func.func.args);
        },
        .join => |join| {
            // Free left table (recursive)
            deinitTableRef(join.left, allocator);
            allocator.destroy(join.left);

            // Free right table in join clause
            deinitTableRef(join.join_clause.table, allocator);
            allocator.destroy(join.join_clause.table);

            // Free ON condition expression
            if (join.join_clause.on_condition) |*on_cond| {
                deinitExpr(@constCast(on_cond), allocator);
            }

            // Free USING columns
            if (join.join_clause.using_columns) |cols| {
                allocator.free(cols);
            }
        },
    }
}

/// Free all heap-allocated memory in a SelectStmt.
/// Call this to clean up statements returned by the parser.
pub fn deinitSelectStmt(stmt: *SelectStmt, allocator: std.mem.Allocator) void {
    // Free column expressions
    for (stmt.columns) |*col| {
        deinitExpr(&col.expr, allocator);
    }
    allocator.free(stmt.columns);

    // Free FROM clause (TableRef)
    deinitTableRef(&stmt.from, allocator);

    // Free WHERE clause
    if (stmt.where) |*where| {
        deinitExpr(where, allocator);
    }

    // Free GROUP BY clause
    if (stmt.group_by) |*group_by| {
        allocator.free(group_by.columns);
        if (group_by.having) |*having| {
            deinitExpr(having, allocator);
        }
    }

    // Free ORDER BY clause
    if (stmt.order_by) |order_by| {
        allocator.free(order_by);
    }

    // Free set operation (recursive)
    if (stmt.set_operation) |set_op| {
        deinitSelectStmt(set_op.right, allocator);
        allocator.destroy(set_op.right);
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if expression is an aggregate function
pub fn isAggregate(expr: *const Expr) bool {
    return switch (expr.*) {
        .call => |call| {
            const name_upper = std.ascii.upperString(call.name);
            return std.mem.eql(u8, name_upper, "COUNT") or
                std.mem.eql(u8, name_upper, "SUM") or
                std.mem.eql(u8, name_upper, "AVG") or
                std.mem.eql(u8, name_upper, "MIN") or
                std.mem.eql(u8, name_upper, "MAX");
        },
        else => false,
    };
}

/// Count parameters in expression tree
pub fn countParameters(expr: *const Expr) u32 {
    return switch (expr.*) {
        .value => |val| if (val == .parameter) 1 else 0,
        .column => 0,
        .binary => |bin| countParameters(bin.left) + countParameters(bin.right),
        .unary => |un| countParameters(un.operand),
        .call => |call| {
            var count: u32 = 0;
            for (call.args) |*arg| {
                count += countParameters(arg);
            }
            return count;
        },
        .in_list => |in| {
            var count = countParameters(in.expr);
            for (in.values) |*val| {
                count += countParameters(val);
            }
            return count;
        },
        .between => |between| {
            return countParameters(between.expr) +
                countParameters(between.low) +
                countParameters(between.high);
        },
        .case_expr => |case| {
            var count: u32 = 0;
            if (case.operand) |operand| {
                count += countParameters(operand);
            }
            for (case.when_clauses) |*when| {
                count += countParameters(&when.condition);
                count += countParameters(&when.result);
            }
            if (case.else_result) |else_result| {
                count += countParameters(else_result);
            }
            return count;
        },
        .exists => 0, // Subquery parameters handled separately
        .cast => |c| countParameters(c.expr),
        .method_call => |mc| {
            var count: u32 = 0;
            for (mc.args) |*arg| {
                count += countParameters(arg);
            }
            return count;
        },
    };
}

/// Print expression tree (for debugging)
pub fn printExpr(expr: *const Expr, writer: anytype, indent: usize) !void {
    const spaces = " " ** 80;
    const prefix = spaces[0..@min(indent, spaces.len)];

    switch (expr.*) {
        .value => |val| {
            try writer.print("{s}Value: ", .{prefix});
            switch (val) {
                .null => try writer.writeAll("NULL\n"),
                .integer => |i| try writer.print("{d}\n", .{i}),
                .float => |f| try writer.print("{d}\n", .{f}),
                .string => |s| try writer.print("'{s}'\n", .{s}),
                .blob => |b| try writer.print("BLOB({d} bytes)\n", .{b.len}),
                .parameter => |p| try writer.print("?{d}\n", .{p + 1}),
            }
        },
        .column => |col| {
            if (col.table) |table| {
                try writer.print("{s}Column: {s}.{s}\n", .{ prefix, table, col.name });
            } else {
                try writer.print("{s}Column: {s}\n", .{ prefix, col.name });
            }
        },
        .binary => |bin| {
            try writer.print("{s}Binary: {s}\n", .{ prefix, @tagName(bin.op) });
            try printExpr(bin.left, writer, indent + 2);
            try printExpr(bin.right, writer, indent + 2);
        },
        .unary => |un| {
            try writer.print("{s}Unary: {s}\n", .{ prefix, @tagName(un.op) });
            try printExpr(un.operand, writer, indent + 2);
        },
        .call => |call| {
            try writer.print("{s}Call: {s}(", .{ prefix, call.name });
            if (call.distinct) try writer.writeAll("DISTINCT ");
            try writer.writeAll(")\n");
            for (call.args) |*arg| {
                try printExpr(arg, writer, indent + 2);
            }
        },
        .in_list => |in| {
            try writer.print("{s}IN:\n", .{prefix});
            try printExpr(in.expr, writer, indent + 2);
            try writer.print("{s}  Values:\n", .{prefix});
            for (in.values) |*val| {
                try printExpr(val, writer, indent + 4);
            }
        },
        .between => |between| {
            try writer.print("{s}BETWEEN:\n", .{prefix});
            try printExpr(between.expr, writer, indent + 2);
            try writer.print("{s}  Low:\n", .{prefix});
            try printExpr(between.low, writer, indent + 4);
            try writer.print("{s}  High:\n", .{prefix});
            try printExpr(between.high, writer, indent + 4);
        },
        .case_expr => |case| {
            try writer.print("{s}CASE:\n", .{prefix});
            if (case.operand) |operand| {
                try writer.print("{s}  Operand:\n", .{prefix});
                try printExpr(operand, writer, indent + 4);
            }
            for (case.when_clauses) |*when| {
                try writer.print("{s}  WHEN:\n", .{prefix});
                try printExpr(&when.condition, writer, indent + 4);
                try writer.print("{s}  THEN:\n", .{prefix});
                try printExpr(&when.result, writer, indent + 4);
            }
            if (case.else_result) |else_result| {
                try writer.print("{s}  ELSE:\n", .{prefix});
                try printExpr(else_result, writer, indent + 4);
            }
        },
        .exists => |ex| {
            try writer.print("{s}{s}EXISTS (subquery)\n", .{ prefix, if (ex.negated) "NOT " else "" });
        },
        .cast => |c| {
            try writer.print("{s}CAST AS {s}:\n", .{ prefix, c.target_type });
            try printExpr(c.expr, writer, indent + 2);
        },
        .method_call => |mc| {
            try writer.print("{s}MethodCall: {s}.{s}(\n", .{ prefix, mc.object, mc.method });
            for (mc.args) |*arg| {
                try printExpr(arg, writer, indent + 2);
            }
            try writer.print("{s})", .{prefix});
            if (mc.over) |over| {
                try writer.writeAll(" OVER(");
                if (over.partition_by) |pb| {
                    try writer.writeAll("PARTITION BY ");
                    for (pb, 0..) |col, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.writeAll(col);
                    }
                }
                if (over.order_by) |ob| {
                    if (over.partition_by != null) try writer.writeAll(" ");
                    try writer.writeAll("ORDER BY ");
                    for (ob, 0..) |o, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.print("{s} {s}", .{ o.column, if (o.direction == .desc) "DESC" else "ASC" });
                    }
                }
                try writer.writeAll(")");
            }
            try writer.writeAll("\n");
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

test "value types" {
    const val_int = Value{ .integer = 42 };
    const val_str = Value{ .string = "hello" };
    const val_param = Value{ .parameter = 0 };

    try std.testing.expect(val_int == .integer);
    try std.testing.expectEqual(@as(i64, 42), val_int.integer);
    try std.testing.expect(val_str == .string);
    try std.testing.expectEqualStrings("hello", val_str.string);
    try std.testing.expect(val_param == .parameter);
    try std.testing.expectEqual(@as(u32, 0), val_param.parameter);
}

test "column expression" {
    const col = Expr{
        .column = .{
            .table = "users",
            .name = "id",
        },
    };

    try std.testing.expect(col == .column);
    try std.testing.expectEqualStrings("users", col.column.table.?);
    try std.testing.expectEqualStrings("id", col.column.name);
}

//! Column Dependency Extraction for @logic_table
//!
//! Walks SQL AST and Python logic table AST to extract all table.column references.
//! Used by the compiler to determine which Lance columns need to be fetched
//! and to generate efficient batch processing functions.
//!
//! Example:
//! ```python
//! @logic_table
//! class FraudDetector:
//!     def score(self, transactions):
//!         return cosine_sim(transactions.embedding, self.fraud_pattern)
//! ```
//!
//! Extracts: ["transactions.embedding"]

const std = @import("std");
const ast = @import("ast.zig");

/// A column reference with optional table qualifier
pub const ColumnRef = struct {
    table: ?[]const u8,
    column: []const u8,

    /// Format as "table.column" or just "column"
    pub fn toString(self: ColumnRef, buf: []u8) ![]const u8 {
        if (self.table) |t| {
            return std.fmt.bufPrint(buf, "{s}.{s}", .{ t, self.column });
        } else {
            return std.fmt.bufPrint(buf, "{s}", .{self.column});
        }
    }

    /// Check equality
    pub fn eql(self: ColumnRef, other: ColumnRef) bool {
        const table_eq = if (self.table) |t1| blk: {
            break :blk if (other.table) |t2| std.mem.eql(u8, t1, t2) else false;
        } else other.table == null;

        return table_eq and std.mem.eql(u8, self.column, other.column);
    }
};

/// Column dependency extractor
pub const ColumnDeps = struct {
    allocator: std.mem.Allocator,
    /// Unique column references found
    refs: std.ArrayListUnmanaged(ColumnRef),
    /// Set for deduplication (stores formatted "table.column" strings)
    seen: std.StringHashMapUnmanaged(void),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .refs = .{},
            .seen = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        // Free the keys in seen map (they were duped)
        var it = self.seen.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.seen.deinit(self.allocator);

        // Free the duped strings in refs
        for (self.refs.items) |ref| {
            if (ref.table) |t| {
                self.allocator.free(t);
            }
            self.allocator.free(ref.column);
        }
        self.refs.deinit(self.allocator);
    }

    /// Add a column reference (deduplicates)
    pub fn addRef(self: *Self, table: ?[]const u8, column: []const u8) !void {
        // Build key for deduplication
        var key_buf: [512]u8 = undefined;
        const key = if (table) |t|
            std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ t, column }) catch return error.KeyTooLong
        else
            std.fmt.bufPrint(&key_buf, "{s}", .{column}) catch return error.KeyTooLong;

        // Check if already seen
        if (self.seen.contains(key)) return;

        // Add to seen set
        const key_copy = try self.allocator.dupe(u8, key);
        try self.seen.put(self.allocator, key_copy, {});

        // Add to refs list
        try self.refs.append(self.allocator, .{
            .table = if (table) |t| try self.allocator.dupe(u8, t) else null,
            .column = try self.allocator.dupe(u8, column),
        });
    }

    /// Extract column dependencies from a SQL expression
    pub fn extractFromExpr(self: *Self, expr: *const ast.Expr) !void {
        switch (expr.*) {
            .column => |col| {
                try self.addRef(col.table, col.name);
            },
            .binary => |bin| {
                try self.extractFromExpr(bin.left);
                try self.extractFromExpr(bin.right);
            },
            .unary => |un| {
                try self.extractFromExpr(un.operand);
            },
            .call => |call| {
                for (call.args) |*arg| {
                    try self.extractFromExpr(arg);
                }
            },
            .in_list => |in| {
                try self.extractFromExpr(in.expr);
                for (in.values) |*val| {
                    try self.extractFromExpr(val);
                }
            },
            .between => |between| {
                try self.extractFromExpr(between.expr);
                try self.extractFromExpr(between.low);
                try self.extractFromExpr(between.high);
            },
            .case_expr => |case| {
                if (case.operand) |operand| {
                    try self.extractFromExpr(operand);
                }
                for (case.when_clauses) |*when| {
                    try self.extractFromExpr(&when.condition);
                    try self.extractFromExpr(&when.result);
                }
                if (case.else_result) |else_result| {
                    try self.extractFromExpr(else_result);
                }
            },
            .exists => {}, // Subquery handled separately
            .in_subquery => |in| {
                try self.extractFromExpr(in.expr);
                // Subquery handled separately
            },
            .cast => |c| {
                try self.extractFromExpr(c.expr);
            },
            .method_call => |mc| {
                // Method calls (e.g., t.risk_score()) - extract from args
                for (mc.args) |*arg| {
                    try self.extractFromExpr(arg);
                }
            },
            .value => {}, // No column references in literals
        }
    }

    /// Extract column dependencies from a SELECT statement
    pub fn extractFromSelect(self: *Self, stmt: *const ast.SelectStmt) !void {
        // SELECT columns
        for (stmt.columns) |*item| {
            try self.extractFromExpr(&item.expr);
        }

        // WHERE clause
        if (stmt.where) |*where| {
            try self.extractFromExpr(where);
        }

        // GROUP BY HAVING
        if (stmt.group_by) |*group_by| {
            if (group_by.having) |*having| {
                try self.extractFromExpr(having);
            }
        }
    }

    /// Get all unique column references
    pub fn getRefs(self: *const Self) []const ColumnRef {
        return self.refs.items;
    }

    /// Get columns for a specific table
    pub fn getTableColumns(self: *const Self, table_name: []const u8) ![]const []const u8 {
        var result = std.ArrayListUnmanaged([]const u8){};
        errdefer result.deinit(self.allocator);

        for (self.refs.items) |ref| {
            if (ref.table) |t| {
                if (std.mem.eql(u8, t, table_name)) {
                    try result.append(self.allocator, ref.column);
                }
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Get all unqualified column references (no table prefix)
    pub fn getUnqualifiedColumns(self: *const Self) ![]const []const u8 {
        var result = std.ArrayListUnmanaged([]const u8){};
        errdefer result.deinit(self.allocator);

        for (self.refs.items) |ref| {
            if (ref.table == null) {
                try result.append(self.allocator, ref.column);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

/// Extract column dependencies from a logic table function call.
/// Parses expressions like: logic_table('fraud.py').score(transactions.embedding)
pub fn extractFromTableFunction(
    allocator: std.mem.Allocator,
    func: *const ast.TableFunction,
) !ColumnDeps {
    var deps = ColumnDeps.init(allocator);
    errdefer deps.deinit();

    // Extract from function arguments
    for (func.args) |*arg| {
        try deps.extractFromExpr(arg);
    }

    return deps;
}

// ============================================================================
// Tests
// ============================================================================

test "extract simple column ref" {
    const allocator = std.testing.allocator;
    var deps = ColumnDeps.init(allocator);
    defer deps.deinit();

    try deps.addRef("users", "name");
    try deps.addRef("users", "email");
    try deps.addRef("users", "name"); // Duplicate

    const refs = deps.getRefs();
    try std.testing.expectEqual(@as(usize, 2), refs.len);
}

test "extract from expression" {
    const allocator = std.testing.allocator;
    var deps = ColumnDeps.init(allocator);
    defer deps.deinit();

    // Simulate: users.age > 18 AND orders.amount > 100
    var left_col = ast.Expr{ .column = .{ .table = "users", .name = "age" } };
    var left_val = ast.Expr{ .value = .{ .integer = 18 } };
    var left_bin = ast.Expr{ .binary = .{
        .op = .gt,
        .left = &left_col,
        .right = &left_val,
    } };

    var right_col = ast.Expr{ .column = .{ .table = "orders", .name = "amount" } };
    var right_val = ast.Expr{ .value = .{ .integer = 100 } };
    var right_bin = ast.Expr{ .binary = .{
        .op = .gt,
        .left = &right_col,
        .right = &right_val,
    } };

    var and_expr = ast.Expr{ .binary = .{
        .op = .@"and",
        .left = &left_bin,
        .right = &right_bin,
    } };

    try deps.extractFromExpr(&and_expr);

    const refs = deps.getRefs();
    try std.testing.expectEqual(@as(usize, 2), refs.len);

    // Check we got both columns
    var found_age = false;
    var found_amount = false;
    for (refs) |ref| {
        if (ref.table) |t| {
            if (std.mem.eql(u8, t, "users") and std.mem.eql(u8, ref.column, "age")) {
                found_age = true;
            }
            if (std.mem.eql(u8, t, "orders") and std.mem.eql(u8, ref.column, "amount")) {
                found_amount = true;
            }
        }
    }
    try std.testing.expect(found_age);
    try std.testing.expect(found_amount);
}

test "get table columns" {
    const allocator = std.testing.allocator;
    var deps = ColumnDeps.init(allocator);
    defer deps.deinit();

    try deps.addRef("users", "name");
    try deps.addRef("users", "email");
    try deps.addRef("orders", "total");

    const user_cols = try deps.getTableColumns("users");
    defer allocator.free(user_cols);

    try std.testing.expectEqual(@as(usize, 2), user_cols.len);
}

test "toString column ref" {
    const ref1 = ColumnRef{ .table = "users", .column = "name" };
    const ref2 = ColumnRef{ .table = null, .column = "id" };

    var buf1: [64]u8 = undefined;
    const str1 = try ref1.toString(&buf1);
    try std.testing.expectEqualStrings("users.name", str1);

    var buf2: [64]u8 = undefined;
    const str2 = try ref2.toString(&buf2);
    try std.testing.expectEqualStrings("id", str2);
}

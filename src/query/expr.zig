//! Expression types and evaluation for SQL WHERE clauses.
//!
//! Supports literals, column references, binary/unary operators,
//! and function calls (aggregates).

const std = @import("std");
pub const Value = @import("lanceql.value").Value;

/// Binary operators for expressions.
pub const BinaryOp = enum {
    // Comparison
    eq, // =
    ne, // != or <>
    lt, // <
    le, // <=
    gt, // >
    ge, // >=

    // Arithmetic
    add, // +
    sub, // -
    mul, // *
    div, // /

    // Logical
    and_, // AND
    or_, // OR

    pub fn fromStr(s: []const u8) ?BinaryOp {
        const map = std.StaticStringMap(BinaryOp).initComptime(.{
            .{ "=", .eq },
            .{ "==", .eq },
            .{ "!=", .ne },
            .{ "<>", .ne },
            .{ "<", .lt },
            .{ "<=", .le },
            .{ ">", .gt },
            .{ ">=", .ge },
            .{ "+", .add },
            .{ "-", .sub },
            .{ "*", .mul },
            .{ "/", .div },
            .{ "AND", .and_ },
            .{ "OR", .or_ },
        });
        return map.get(s);
    }

    pub fn precedence(self: BinaryOp) u8 {
        return switch (self) {
            .or_ => 1,
            .and_ => 2,
            .eq, .ne, .lt, .le, .gt, .ge => 3,
            .add, .sub => 4,
            .mul, .div => 5,
        };
    }
};

/// Unary operators.
pub const UnaryOp = enum {
    not, // NOT
    neg, // - (negation)

    pub fn fromStr(s: []const u8) ?UnaryOp {
        if (std.ascii.eqlIgnoreCase(s, "NOT")) return .not;
        if (std.mem.eql(u8, s, "-")) return .neg;
        return null;
    }
};

/// An expression node in the AST.
pub const Expr = union(enum) {
    /// Literal value (number, string, boolean, null)
    literal: Value,

    /// Column reference by name
    column: []const u8,

    /// Binary operation (a op b)
    binary: Binary,

    /// Unary operation (op a)
    unary: Unary,

    /// Function call (COUNT, SUM, etc.)
    call: Call,

    /// Star (*) for SELECT *
    star,

    pub const Binary = struct {
        op: BinaryOp,
        left: *Expr,
        right: *Expr,
    };

    pub const Unary = struct {
        op: UnaryOp,
        operand: *Expr,
    };

    pub const Call = struct {
        name: []const u8,
        args: []Expr,
        distinct: bool = false,
    };

    const Self = @This();

    // ========================================================================
    // Constructors (for building expressions programmatically)
    // ========================================================================

    pub fn lit(value: Value) Self {
        return .{ .literal = value };
    }

    pub fn col(name: []const u8) Self {
        return .{ .column = name };
    }

    pub fn intLit(v: i64) Self {
        return .{ .literal = Value.int(v) };
    }

    pub fn floatLit(v: f64) Self {
        return .{ .literal = Value.float(v) };
    }

    pub fn strLit(v: []const u8) Self {
        return .{ .literal = Value.str(v) };
    }

    pub fn boolLit(v: bool) Self {
        return .{ .literal = Value.boolean(v) };
    }

    pub fn nullLit() Self {
        return .{ .literal = Value.nil() };
    }

    // ========================================================================
    // Evaluation
    // ========================================================================

    pub const EvalError = error{
        ColumnNotFound,
        TypeMismatch,
        DivisionByZero,
        NullValue,
        UnsupportedFunction,
    };

    /// Evaluate expression against a row of values.
    /// `columns` maps column names to indices in `row`.
    pub fn eval(
        self: Self,
        row: []const Value,
        columns: std.StringHashMap(usize),
    ) EvalError!Value {
        return switch (self) {
            .literal => |v| v,
            .column => |name| {
                const idx = columns.get(name) orelse return error.ColumnNotFound;
                return row[idx];
            },
            .binary => |b| {
                const left = try b.left.eval(row, columns);
                const right = try b.right.eval(row, columns);
                return evalBinary(b.op, left, right);
            },
            .unary => |u| {
                const operand = try u.operand.eval(row, columns);
                return evalUnary(u.op, operand);
            },
            .call => error.UnsupportedFunction, // Aggregates handled separately
            .star => error.UnsupportedFunction,
        };
    }

    fn evalBinary(op: BinaryOp, left: Value, right: Value) EvalError!Value {
        return switch (op) {
            // Comparison operators return boolean
            .eq => Value.boolean(left.eql(right)),
            .ne => Value.boolean(!left.eql(right)),
            .lt => Value.boolean(left.lessThan(right)),
            .le => Value.boolean(left.lessThan(right) or left.eql(right)),
            .gt => Value.boolean(left.greaterThan(right)),
            .ge => Value.boolean(left.greaterThan(right) or left.eql(right)),

            // Arithmetic
            .add => Value.add(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
            .sub => Value.sub(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
            .mul => Value.mul(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
            .div => Value.div(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },

            // Logical
            .and_ => Value.logicalAnd(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
            .or_ => Value.logicalOr(left, right) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
        };
    }

    fn evalUnary(op: UnaryOp, operand: Value) EvalError!Value {
        return switch (op) {
            .not => Value.logicalNot(operand) catch |e| switch (e) {
                error.TypeMismatch => error.TypeMismatch,
                error.DivisionByZero => error.DivisionByZero,
                error.NullValue => error.NullValue,
            },
            .neg => switch (operand) {
                .int64 => |v| Value.int(-v),
                .float64 => |v| Value.float(-v),
                else => error.TypeMismatch,
            },
        };
    }

    // ========================================================================
    // Utility
    // ========================================================================

    /// Check if expression is an aggregate function call.
    pub fn isAggregate(self: Self) bool {
        return switch (self) {
            .call => |c| isAggregateFunc(c.name),
            else => false,
        };
    }

    /// Get referenced column names.
    pub fn getColumns(self: Self, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayListUnmanaged([]const u8){};
        try self.collectColumns(allocator, &list);
        return list.toOwnedSlice(allocator);
    }

    fn collectColumns(self: Self, allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8)) !void {
        switch (self) {
            .column => |name| try list.append(allocator, name),
            .binary => |b| {
                try b.left.collectColumns(allocator, list);
                try b.right.collectColumns(allocator, list);
            },
            .unary => |u| try u.operand.collectColumns(allocator, list),
            .call => |c| {
                for (c.args) |arg| {
                    try arg.collectColumns(allocator, list);
                }
            },
            .literal, .star => {},
        }
    }
};

fn isAggregateFunc(name: []const u8) bool {
    const aggs = [_][]const u8{ "COUNT", "SUM", "AVG", "MIN", "MAX" };
    for (aggs) |agg| {
        if (std.ascii.eqlIgnoreCase(name, agg)) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "Expr literal evaluation" {
    const expr = Expr.intLit(42);
    var columns = std.StringHashMap(usize).init(std.testing.allocator);
    defer columns.deinit();

    const result = try expr.eval(&.{}, columns);
    try std.testing.expectEqual(result.int64, 42);
}

test "Expr column evaluation" {
    const expr = Expr.col("id");
    var columns = std.StringHashMap(usize).init(std.testing.allocator);
    defer columns.deinit();
    try columns.put("id", 0);

    const row = [_]Value{Value.int(123)};
    const result = try expr.eval(&row, columns);
    try std.testing.expectEqual(result.int64, 123);
}

test "BinaryOp precedence" {
    try std.testing.expect(BinaryOp.mul.precedence() > BinaryOp.add.precedence());
    try std.testing.expect(BinaryOp.and_.precedence() > BinaryOp.or_.precedence());
    try std.testing.expect(BinaryOp.eq.precedence() > BinaryOp.and_.precedence());
}

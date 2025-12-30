//! Unified Value type for query operations.
//!
//! Provides a tagged union representing all supported Lance column types,
//! with comparison and arithmetic operations for expression evaluation.

const std = @import("std");

/// A runtime value that can hold any supported Lance data type.
pub const Value = union(enum) {
    null,
    int64: i64,
    float64: f64,
    bool_: bool,
    string: []const u8,

    const Self = @This();

    // ========================================================================
    // Constructors
    // ========================================================================

    pub fn int(v: i64) Self {
        return .{ .int64 = v };
    }

    pub fn float(v: f64) Self {
        return .{ .float64 = v };
    }

    pub fn boolean(v: bool) Self {
        return .{ .bool_ = v };
    }

    pub fn str(v: []const u8) Self {
        return .{ .string = v };
    }

    pub fn nil() Self {
        return .null;
    }

    // ========================================================================
    // Type checking
    // ========================================================================

    pub fn isNull(self: Self) bool {
        return self == .null;
    }

    pub fn isNumeric(self: Self) bool {
        return self == .int64 or self == .float64;
    }

    // ========================================================================
    // Comparison
    // ========================================================================

    pub const Order = std.math.Order;

    /// Compare two values. Returns null if types are incompatible.
    pub fn compare(a: Self, b: Self) ?Order {
        // Null comparisons
        if (a == .null and b == .null) return .eq;
        if (a == .null or b == .null) return null;

        // Same type comparisons
        return switch (a) {
            .null => unreachable,
            .int64 => |av| switch (b) {
                .int64 => |bv| order(av, bv),
                .float64 => |bv| order(@as(f64, @floatFromInt(av)), bv),
                else => null,
            },
            .float64 => |av| switch (b) {
                .float64 => |bv| order(av, bv),
                .int64 => |bv| order(av, @as(f64, @floatFromInt(bv))),
                else => null,
            },
            .bool_ => |av| switch (b) {
                .bool_ => |bv| order(@intFromBool(av), @intFromBool(bv)),
                else => null,
            },
            .string => |av| switch (b) {
                .string => |bv| std.mem.order(u8, av, bv),
                else => null,
            },
        };
    }

    fn order(a: anytype, b: @TypeOf(a)) Order {
        return std.math.order(a, b);
    }

    pub fn eql(a: Self, b: Self) bool {
        const ord = compare(a, b) orelse return false;
        return ord == .eq;
    }

    pub fn lessThan(a: Self, b: Self) bool {
        const ord = compare(a, b) orelse return false;
        return ord == .lt;
    }

    pub fn greaterThan(a: Self, b: Self) bool {
        const ord = compare(a, b) orelse return false;
        return ord == .gt;
    }

    // ========================================================================
    // Arithmetic
    // ========================================================================

    pub const ArithmeticError = error{
        TypeMismatch,
        DivisionByZero,
        NullValue,
    };

    pub fn add(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .int64 => |av| switch (b) {
                .int64 => |bv| .{ .int64 = av + bv },
                .float64 => |bv| .{ .float64 = @as(f64, @floatFromInt(av)) + bv },
                else => error.TypeMismatch,
            },
            .float64 => |av| switch (b) {
                .float64 => |bv| .{ .float64 = av + bv },
                .int64 => |bv| .{ .float64 = av + @as(f64, @floatFromInt(bv)) },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    pub fn sub(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .int64 => |av| switch (b) {
                .int64 => |bv| .{ .int64 = av - bv },
                .float64 => |bv| .{ .float64 = @as(f64, @floatFromInt(av)) - bv },
                else => error.TypeMismatch,
            },
            .float64 => |av| switch (b) {
                .float64 => |bv| .{ .float64 = av - bv },
                .int64 => |bv| .{ .float64 = av - @as(f64, @floatFromInt(bv)) },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    pub fn mul(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .int64 => |av| switch (b) {
                .int64 => |bv| .{ .int64 = av * bv },
                .float64 => |bv| .{ .float64 = @as(f64, @floatFromInt(av)) * bv },
                else => error.TypeMismatch,
            },
            .float64 => |av| switch (b) {
                .float64 => |bv| .{ .float64 = av * bv },
                .int64 => |bv| .{ .float64 = av * @as(f64, @floatFromInt(bv)) },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    pub fn div(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .int64 => |av| switch (b) {
                .int64 => |bv| {
                    if (bv == 0) return error.DivisionByZero;
                    return .{ .int64 = @divTrunc(av, bv) };
                },
                .float64 => |bv| {
                    if (bv == 0) return error.DivisionByZero;
                    return .{ .float64 = @as(f64, @floatFromInt(av)) / bv };
                },
                else => error.TypeMismatch,
            },
            .float64 => |av| switch (b) {
                .float64 => |bv| {
                    if (bv == 0) return error.DivisionByZero;
                    return .{ .float64 = av / bv };
                },
                .int64 => |bv| {
                    if (bv == 0) return error.DivisionByZero;
                    return .{ .float64 = av / @as(f64, @floatFromInt(bv)) };
                },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    // ========================================================================
    // Logical operations
    // ========================================================================

    pub fn logicalAnd(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .bool_ => |av| switch (b) {
                .bool_ => |bv| .{ .bool_ = av and bv },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    pub fn logicalOr(a: Self, b: Self) ArithmeticError!Self {
        if (a == .null or b == .null) return error.NullValue;

        return switch (a) {
            .bool_ => |av| switch (b) {
                .bool_ => |bv| .{ .bool_ = av or bv },
                else => error.TypeMismatch,
            },
            else => error.TypeMismatch,
        };
    }

    pub fn logicalNot(self: Self) ArithmeticError!Self {
        if (self == .null) return error.NullValue;

        return switch (self) {
            .bool_ => |v| .{ .bool_ = !v },
            else => error.TypeMismatch,
        };
    }

    // ========================================================================
    // Conversion
    // ========================================================================

    pub fn toInt64(self: Self) ?i64 {
        return switch (self) {
            .int64 => |v| v,
            .float64 => |v| @intFromFloat(v),
            .bool_ => |v| @intFromBool(v),
            else => null,
        };
    }

    pub fn toFloat64(self: Self) ?f64 {
        return switch (self) {
            .float64 => |v| v,
            .int64 => |v| @floatFromInt(v),
            else => null,
        };
    }

    pub fn toBool(self: Self) ?bool {
        return switch (self) {
            .bool_ => |v| v,
            .int64 => |v| v != 0,
            else => null,
        };
    }

    // ========================================================================
    // Formatting
    // ========================================================================

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .null => try writer.writeAll("NULL"),
            .int64 => |v| try writer.print("{d}", .{v}),
            .float64 => |v| try writer.print("{d:.6}", .{v}),
            .bool_ => |v| try writer.writeAll(if (v) "true" else "false"),
            .string => |v| try writer.print("\"{s}\"", .{v}),
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Value comparison" {
    const a = Value.int(10);
    const b = Value.int(20);
    const c = Value.int(10);

    try std.testing.expect(a.lessThan(b));
    try std.testing.expect(b.greaterThan(a));
    try std.testing.expect(a.eql(c));
}

test "Value arithmetic" {
    const a = Value.int(10);
    const b = Value.int(3);

    const sum = try Value.add(a, b);
    try std.testing.expectEqual(sum.int64, 13);

    const diff = try Value.sub(a, b);
    try std.testing.expectEqual(diff.int64, 7);

    const prod = try Value.mul(a, b);
    try std.testing.expectEqual(prod.int64, 30);

    const quot = try Value.div(a, b);
    try std.testing.expectEqual(quot.int64, 3);
}

test "Value mixed numeric" {
    const a = Value.int(10);
    const b = Value.float(2.5);

    const sum = try Value.add(a, b);
    try std.testing.expectApproxEqAbs(sum.float64, 12.5, 0.001);
}

test "Value logical" {
    const t = Value.boolean(true);
    const f = Value.boolean(false);

    const and_result = try Value.logicalAnd(t, f);
    try std.testing.expectEqual(and_result.bool_, false);

    const or_result = try Value.logicalOr(t, f);
    try std.testing.expectEqual(or_result.bool_, true);

    const not_result = try Value.logicalNot(t);
    try std.testing.expectEqual(not_result.bool_, false);
}

test "Value null handling" {
    const n = Value.nil();
    const a = Value.int(10);

    try std.testing.expect(n.isNull());
    try std.testing.expect(!a.isNull());

    // Null arithmetic returns error
    try std.testing.expectError(error.NullValue, Value.add(n, a));
}

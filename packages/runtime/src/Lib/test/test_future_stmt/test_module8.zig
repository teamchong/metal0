//! test.test_future_stmt.test_barry - Tests for `from __future__ import barry_as_FLUFL`
//!
//! PEP 401 (April Fools' joke from 2009) introduced barry_as_FLUFL.
//! When enabled, the not-equal operator `!=` must be written as `<>` instead.
//! This is a reference to Barry Warsaw, Python's first FLUFL (Friendly Language
//! Uncle For Life), who preferred the `<>` syntax.
//!
//! This module tests alternative operator syntax and parsing.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 401: https://peps.python.org/pep-0401/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Operator Alternatives
// ============================================================================

/// Represents different operator syntax styles
pub const OperatorStyle = enum {
    /// Standard Python 3 style: !=
    standard,
    /// Barry's FLUFL style: <>
    flufl,
    /// Python 2 supported both
    legacy,

    pub fn name(self: OperatorStyle) []const u8 {
        return switch (self) {
            .standard => "standard (!=)",
            .flufl => "FLUFL (<>)",
            .legacy => "legacy (both)",
        };
    }

    /// Get the not-equal operator for this style
    pub fn notEqualOp(self: OperatorStyle) []const u8 {
        return switch (self) {
            .standard => "!=",
            .flufl => "<>",
            .legacy => "!= or <>",
        };
    }
};

/// Comparison operators
pub const ComparisonOp = enum {
    eq, // ==
    ne, // != or <>
    lt, // <
    le, // <=
    gt, // >
    ge, // >=

    pub fn symbol(self: ComparisonOp, style: OperatorStyle) []const u8 {
        return switch (self) {
            .eq => "==",
            .ne => if (style == .flufl) "<>" else "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
        };
    }

    /// Parse operator from string
    pub fn parse(op_str: []const u8) ?ComparisonOp {
        if (std.mem.eql(u8, op_str, "==")) return .eq;
        if (std.mem.eql(u8, op_str, "!=")) return .ne;
        if (std.mem.eql(u8, op_str, "<>")) return .ne;
        if (std.mem.eql(u8, op_str, "<")) return .lt;
        if (std.mem.eql(u8, op_str, "<=")) return .le;
        if (std.mem.eql(u8, op_str, ">")) return .gt;
        if (std.mem.eql(u8, op_str, ">=")) return .ge;
        return null;
    }

    /// Get the inverse operator
    pub fn invert(self: ComparisonOp) ComparisonOp {
        return switch (self) {
            .eq => .ne,
            .ne => .eq,
            .lt => .ge,
            .le => .gt,
            .gt => .le,
            .ge => .lt,
        };
    }
};

// ============================================================================
// FLUFL Mode Context
// ============================================================================

/// Context manager for enabling FLUFL mode
pub const FLUFLContext = struct {
    enabled: bool,
    previous_state: bool = false,

    /// Global state for FLUFL mode
    var is_flufl_mode: bool = false;

    const Self = @This();

    pub fn init(enable: bool) Self {
        return .{ .enabled = enable };
    }

    pub fn __enter__(self: *Self) *Self {
        self.previous_state = is_flufl_mode;
        is_flufl_mode = self.enabled;
        return self;
    }

    pub fn __exit__(self: *Self) void {
        is_flufl_mode = self.previous_state;
    }

    /// Check if FLUFL mode is currently enabled
    pub fn isEnabled() bool {
        return is_flufl_mode;
    }

    /// Get the current operator style
    pub fn currentStyle() OperatorStyle {
        return if (is_flufl_mode) .flufl else .standard;
    }
};

// ============================================================================
// Operator Validator
// ============================================================================

/// Validates operator syntax based on current mode
pub const OperatorValidator = struct {
    style: OperatorStyle,

    const Self = @This();

    pub fn init(style: OperatorStyle) Self {
        return .{ .style = style };
    }

    /// Check if an operator is valid in current mode
    pub fn isValidOperator(self: Self, op: []const u8) bool {
        switch (self.style) {
            .standard => {
                // In standard mode, != is valid, <> is not for not-equal
                if (std.mem.eql(u8, op, "<>")) return false;
                return ComparisonOp.parse(op) != null;
            },
            .flufl => {
                // In FLUFL mode, <> is valid, != is not for not-equal
                if (std.mem.eql(u8, op, "!=")) return false;
                return ComparisonOp.parse(op) != null;
            },
            .legacy => {
                // Legacy mode accepts both
                return ComparisonOp.parse(op) != null;
            },
        }
    }

    /// Get error message for invalid operator
    pub fn getErrorMessage(self: Self, op: []const u8) []const u8 {
        if (std.mem.eql(u8, op, "!=") and self.style == .flufl) {
            return "SyntaxError: with barry_as_FLUFL, use '<>' instead of '!='";
        }
        if (std.mem.eql(u8, op, "<>") and self.style == .standard) {
            return "SyntaxError: invalid syntax, use '!=' for not-equal";
        }
        return "SyntaxError: invalid operator";
    }
};

// ============================================================================
// Comparison Expression
// ============================================================================

/// Represents a comparison expression
pub const ComparisonExpr = struct {
    left: i64,
    op: ComparisonOp,
    right: i64,
    op_text: []const u8,

    const Self = @This();

    pub fn init(left: i64, op: ComparisonOp, right: i64) Self {
        return .{
            .left = left,
            .op = op,
            .right = right,
            .op_text = op.symbol(.standard),
        };
    }

    /// Create with explicit operator text
    pub fn withOpText(left: i64, op_text: []const u8, right: i64) !Self {
        const op = ComparisonOp.parse(op_text) orelse return error.InvalidOperator;
        return .{
            .left = left,
            .op = op,
            .right = right,
            .op_text = op_text,
        };
    }

    /// Evaluate the comparison
    pub fn evaluate(self: Self) bool {
        return switch (self.op) {
            .eq => self.left == self.right,
            .ne => self.left != self.right,
            .lt => self.left < self.right,
            .le => self.left <= self.right,
            .gt => self.left > self.right,
            .ge => self.left >= self.right,
        };
    }

    /// Format as string
    pub fn format(self: Self, style: OperatorStyle) ![]const u8 {
        _ = self;
        _ = style;
        // Would format as "left op right"
        return "comparison";
    }
};

// ============================================================================
// Syntax Transformer
// ============================================================================

/// Transforms between FLUFL and standard syntax
pub const SyntaxTransformer = struct {
    const Self = @This();

    /// Convert FLUFL syntax to standard
    pub fn fluflToStandard(allocator: std.mem.Allocator, code: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        var i: usize = 0;

        while (i < code.len) {
            if (i + 1 < code.len and code[i] == '<' and code[i + 1] == '>') {
                try result.appendSlice(allocator, "!=");
                i += 2;
            } else {
                try result.append(allocator, code[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Convert standard syntax to FLUFL
    pub fn standardToFlufl(allocator: std.mem.Allocator, code: []const u8) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        var i: usize = 0;

        while (i < code.len) {
            if (i + 1 < code.len and code[i] == '!' and code[i + 1] == '=') {
                try result.appendSlice(allocator, "<>");
                i += 2;
            } else {
                try result.append(allocator, code[i]);
                i += 1;
            }
        }

        return try result.toOwnedSlice(allocator);
    }

    /// Count operators in code
    pub fn countOperators(code: []const u8) struct { ne_count: usize, diamond_count: usize } {
        var ne_count: usize = 0;
        var diamond_count: usize = 0;
        var i: usize = 0;

        while (i < code.len) {
            if (i + 1 < code.len) {
                if (code[i] == '!' and code[i + 1] == '=') {
                    ne_count += 1;
                    i += 2;
                    continue;
                }
                if (code[i] == '<' and code[i + 1] == '>') {
                    diamond_count += 1;
                    i += 2;
                    continue;
                }
            }
            i += 1;
        }

        return .{ .ne_count = ne_count, .diamond_count = diamond_count };
    }
};

// ============================================================================
// FLUFL History (April Fools' References)
// ============================================================================

/// Information about the FLUFL tradition
pub const FLUFLInfo = struct {
    /// The title: Friendly Language Uncle For Life
    pub const title = "Friendly Language Uncle For Life";

    /// The PEP number
    pub const pep_number: u32 = 401;

    /// The date (April Fools' Day 2009)
    pub const pep_date = "April 1, 2009";

    /// The author
    pub const author = "Barry Warsaw";

    /// Check if a date is April Fools' Day
    pub fn isAprilFools(month: u8, day: u8) bool {
        return month == 4 and day == 1;
    }

    /// Get a FLUFL greeting
    pub fn getGreeting() []const u8 {
        return "Long live the diamond operator!";
    }

    /// Get mandatory FLUFL message
    pub fn getMandatoryMessage() []const u8 {
        return "In FLUFL mode, you must use <> instead of !=";
    }
};

// ============================================================================
// Operator Statistics
// ============================================================================

/// Collects statistics about operator usage
pub const OperatorStats = struct {
    eq_count: usize = 0,
    ne_count: usize = 0,
    lt_count: usize = 0,
    le_count: usize = 0,
    gt_count: usize = 0,
    ge_count: usize = 0,
    diamond_count: usize = 0,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Record an operator usage
    pub fn record(self: *Self, op: ComparisonOp) void {
        switch (op) {
            .eq => self.eq_count += 1,
            .ne => self.ne_count += 1,
            .lt => self.lt_count += 1,
            .le => self.le_count += 1,
            .gt => self.gt_count += 1,
            .ge => self.ge_count += 1,
        }
    }

    /// Record a diamond operator (<>) separately
    pub fn recordDiamond(self: *Self) void {
        self.diamond_count += 1;
    }

    /// Get total comparison count
    pub fn totalComparisons(self: Self) usize {
        return self.eq_count + self.ne_count + self.lt_count +
            self.le_count + self.gt_count + self.ge_count;
    }

    /// Get FLUFL compliance ratio
    pub fn fluflCompliance(self: Self) f64 {
        const total_ne = self.ne_count + self.diamond_count;
        if (total_ne == 0) return 1.0;
        return @as(f64, @floatFromInt(self.diamond_count)) / @as(f64, @floatFromInt(total_ne));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "operator_style_names" {
    try testing.expectEqualStrings("standard (!=)", OperatorStyle.standard.name());
    try testing.expectEqualStrings("FLUFL (<>)", OperatorStyle.flufl.name());
    try testing.expectEqualStrings("legacy (both)", OperatorStyle.legacy.name());
}

test "operator_style_not_equal_op" {
    try testing.expectEqualStrings("!=", OperatorStyle.standard.notEqualOp());
    try testing.expectEqualStrings("<>", OperatorStyle.flufl.notEqualOp());
}

test "comparison_op_parse" {
    try testing.expectEqual(ComparisonOp.eq, ComparisonOp.parse("==").?);
    try testing.expectEqual(ComparisonOp.ne, ComparisonOp.parse("!=").?);
    try testing.expectEqual(ComparisonOp.ne, ComparisonOp.parse("<>").?);
    try testing.expectEqual(ComparisonOp.lt, ComparisonOp.parse("<").?);
    try testing.expect(ComparisonOp.parse("??") == null);
}

test "comparison_op_symbol" {
    try testing.expectEqualStrings("!=", ComparisonOp.ne.symbol(.standard));
    try testing.expectEqualStrings("<>", ComparisonOp.ne.symbol(.flufl));
    try testing.expectEqualStrings("==", ComparisonOp.eq.symbol(.standard));
}

test "comparison_op_invert" {
    try testing.expectEqual(ComparisonOp.ne, ComparisonOp.eq.invert());
    try testing.expectEqual(ComparisonOp.eq, ComparisonOp.ne.invert());
    try testing.expectEqual(ComparisonOp.ge, ComparisonOp.lt.invert());
    try testing.expectEqual(ComparisonOp.gt, ComparisonOp.le.invert());
}

test "flufl_context_manager" {
    try testing.expect(!FLUFLContext.isEnabled());

    var ctx = FLUFLContext.init(true);
    _ = ctx.__enter__();
    try testing.expect(FLUFLContext.isEnabled());
    try testing.expectEqual(OperatorStyle.flufl, FLUFLContext.currentStyle());
    ctx.__exit__();

    try testing.expect(!FLUFLContext.isEnabled());
    try testing.expectEqual(OperatorStyle.standard, FLUFLContext.currentStyle());
}

test "operator_validator_standard" {
    const validator = OperatorValidator.init(.standard);

    try testing.expect(validator.isValidOperator("!="));
    try testing.expect(validator.isValidOperator("=="));
    try testing.expect(!validator.isValidOperator("<>"));
}

test "operator_validator_flufl" {
    const validator = OperatorValidator.init(.flufl);

    try testing.expect(validator.isValidOperator("<>"));
    try testing.expect(validator.isValidOperator("=="));
    try testing.expect(!validator.isValidOperator("!="));
}

test "operator_validator_legacy" {
    const validator = OperatorValidator.init(.legacy);

    try testing.expect(validator.isValidOperator("!="));
    try testing.expect(validator.isValidOperator("<>"));
}

test "comparison_expr_evaluate" {
    const eq_expr = ComparisonExpr.init(5, .eq, 5);
    try testing.expect(eq_expr.evaluate());

    const ne_expr = ComparisonExpr.init(5, .ne, 3);
    try testing.expect(ne_expr.evaluate());

    const lt_expr = ComparisonExpr.init(3, .lt, 5);
    try testing.expect(lt_expr.evaluate());

    const ge_expr = ComparisonExpr.init(5, .ge, 5);
    try testing.expect(ge_expr.evaluate());
}

test "syntax_transformer_flufl_to_standard" {
    const result = try SyntaxTransformer.fluflToStandard(testing.allocator, "a <> b");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a != b", result);
}

test "syntax_transformer_standard_to_flufl" {
    const result = try SyntaxTransformer.standardToFlufl(testing.allocator, "a != b");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("a <> b", result);
}

test "syntax_transformer_count_operators" {
    const counts = SyntaxTransformer.countOperators("a != b and c <> d and e != f");
    try testing.expectEqual(@as(usize, 2), counts.ne_count);
    try testing.expectEqual(@as(usize, 1), counts.diamond_count);
}

test "flufl_info_constants" {
    try testing.expectEqualStrings("Friendly Language Uncle For Life", FLUFLInfo.title);
    try testing.expectEqual(@as(u32, 401), FLUFLInfo.pep_number);
    try testing.expectEqualStrings("Barry Warsaw", FLUFLInfo.author);
}

test "flufl_info_april_fools" {
    try testing.expect(FLUFLInfo.isAprilFools(4, 1));
    try testing.expect(!FLUFLInfo.isAprilFools(4, 2));
    try testing.expect(!FLUFLInfo.isAprilFools(3, 1));
}

test "operator_stats_record" {
    var stats = OperatorStats.init();

    stats.record(.eq);
    stats.record(.eq);
    stats.record(.ne);
    stats.recordDiamond();

    try testing.expectEqual(@as(usize, 2), stats.eq_count);
    try testing.expectEqual(@as(usize, 1), stats.ne_count);
    try testing.expectEqual(@as(usize, 1), stats.diamond_count);
}

test "operator_stats_total" {
    var stats = OperatorStats.init();

    stats.record(.eq);
    stats.record(.lt);
    stats.record(.gt);

    try testing.expectEqual(@as(usize, 3), stats.totalComparisons());
}

test "operator_stats_flufl_compliance" {
    var stats = OperatorStats.init();

    // All diamond operators = 100% compliance
    stats.recordDiamond();
    stats.recordDiamond();
    try testing.expectApproxEqAbs(@as(f64, 1.0), stats.fluflCompliance(), 0.001);

    // Mix of != and <> = 50% compliance
    var stats2 = OperatorStats.init();
    stats2.record(.ne);
    stats2.recordDiamond();
    try testing.expectApproxEqAbs(@as(f64, 0.5), stats2.fluflCompliance(), 0.001);
}

test "validator_error_messages" {
    const flufl_validator = OperatorValidator.init(.flufl);
    const std_validator = OperatorValidator.init(.standard);

    try testing.expect(std.mem.indexOf(u8, flufl_validator.getErrorMessage("!="), "barry_as_FLUFL") != null);
    try testing.expect(std.mem.indexOf(u8, std_validator.getErrorMessage("<>"), "invalid syntax") != null);
}

test "comparison_expr_with_op_text" {
    const expr = try ComparisonExpr.withOpText(5, "<>", 3);
    try testing.expectEqual(ComparisonOp.ne, expr.op);
    try testing.expect(expr.evaluate());
}

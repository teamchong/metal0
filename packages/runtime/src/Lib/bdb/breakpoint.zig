//! Breakpoint class and management.
//!
//! Provides the Breakpoint descriptor that tracks:
//! - Location (file, line, function)
//! - State (enabled, hits, ignore count)
//! - Condition evaluation
//! - Display formatting

const std = @import("std");
const types = @import("types.zig");
const FrameInfo = types.FrameInfo;
const CompareOp = types.CompareOp;

// ============================================================================
// Breakpoint Class
// ============================================================================

/// Breakpoint descriptor
pub const Breakpoint = struct {
    const Self = @This();

    number: usize,
    file: []const u8,
    line: usize,
    temporary: bool,
    cond: ?[]const u8,
    funcname: ?[]const u8,
    enabled: bool,
    hits: usize,
    ignore: usize,

    /// Create a new breakpoint
    pub fn init(
        number: usize,
        file: []const u8,
        line: usize,
        temporary: bool,
        cond: ?[]const u8,
        funcname: ?[]const u8,
    ) Self {
        return .{
            .number = number,
            .file = file,
            .line = line,
            .temporary = temporary,
            .cond = cond,
            .funcname = funcname,
            .enabled = true,
            .hits = 0,
            .ignore = 0,
        };
    }

    /// Enable the breakpoint
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable the breakpoint
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Delete condition
    pub fn deleteCondition(self: *Self) void {
        self.cond = null;
    }

    /// Get breakpoint info string
    pub fn bpformat(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        const disp = if (self.temporary) "del  " else "keep ";
        const enab = if (self.enabled) "yes" else "no ";

        var buf: [256]u8 = undefined;
        const info = std.fmt.bufPrint(&buf, "{d:<4} {s} {s}  at {s}:{d}", .{
            self.number,
            disp,
            enab,
            self.file,
            self.line,
        }) catch return result.toOwnedSlice();

        try result.appendSlice(info);

        if (self.cond) |cond| {
            try result.appendSlice("\n\tstop only if ");
            try result.appendSlice(cond);
        }

        if (self.ignore > 0) {
            var ignore_buf: [64]u8 = undefined;
            const ignore_str = std.fmt.bufPrint(&ignore_buf, "\n\tignore next {d} hits", .{self.ignore}) catch "";
            try result.appendSlice(ignore_str);
        }

        if (self.hits > 0) {
            var hits_buf: [64]u8 = undefined;
            const hits_str = std.fmt.bufPrint(&hits_buf, "\n\tbreakpoint already hit {d} time(s)", .{self.hits}) catch "";
            try result.appendSlice(hits_str);
        }

        return result.toOwnedSlice();
    }

    /// Evaluate a breakpoint condition expression
    /// Supports simple comparisons: x == value, x != value, x > value, x < value
    /// Also supports: True, False, and simple variable existence checks
    pub fn evaluateCondition(cond: []const u8, frame: ?*FrameInfo) bool {
        const trimmed = std.mem.trim(u8, cond, " \t\n\r");

        // Handle literal True/False
        if (std.mem.eql(u8, trimmed, "True") or std.mem.eql(u8, trimmed, "true")) {
            return true;
        }
        if (std.mem.eql(u8, trimmed, "False") or std.mem.eql(u8, trimmed, "false")) {
            return false;
        }

        // Handle comparisons
        if (std.mem.indexOf(u8, trimmed, "==")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 2 ..], .eq, frame);
        }
        if (std.mem.indexOf(u8, trimmed, "!=")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 2 ..], .ne, frame);
        }
        if (std.mem.indexOf(u8, trimmed, ">=")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 2 ..], .ge, frame);
        }
        if (std.mem.indexOf(u8, trimmed, "<=")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 2 ..], .le, frame);
        }
        if (std.mem.indexOf(u8, trimmed, ">")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 1 ..], .gt, frame);
        }
        if (std.mem.indexOf(u8, trimmed, "<")) |pos| {
            return evaluateComparison(trimmed[0..pos], trimmed[pos + 1 ..], .lt, frame);
        }

        // Check if it's a variable that exists and is truthy
        if (frame) |f| {
            if (f.locals.get(trimmed)) |val| {
                // Non-zero and non-empty values are truthy
                return !std.mem.eql(u8, val, "0") and !std.mem.eql(u8, val, "") and !std.mem.eql(u8, val, "None");
            }
        }

        // Unknown condition - default to true (break)
        return true;
    }

    fn evaluateComparison(left: []const u8, right: []const u8, op: CompareOp, frame: ?*FrameInfo) bool {
        const lhs = std.mem.trim(u8, left, " \t");
        const rhs = std.mem.trim(u8, right, " \t");

        // Get values (from frame locals or as literals)
        const lhs_val = getConditionValue(lhs, frame);
        const rhs_val = getConditionValue(rhs, frame);

        // Try numeric comparison first
        const lhs_num = std.fmt.parseInt(i64, lhs_val, 10) catch null;
        const rhs_num = std.fmt.parseInt(i64, rhs_val, 10) catch null;

        if (lhs_num != null and rhs_num != null) {
            const l = lhs_num.?;
            const r = rhs_num.?;
            return switch (op) {
                .eq => l == r,
                .ne => l != r,
                .gt => l > r,
                .lt => l < r,
                .ge => l >= r,
                .le => l <= r,
            };
        }

        // Fall back to string comparison
        const cmp = std.mem.order(u8, lhs_val, rhs_val);
        return switch (op) {
            .eq => cmp == .eq,
            .ne => cmp != .eq,
            .gt => cmp == .gt,
            .lt => cmp == .lt,
            .ge => cmp == .gt or cmp == .eq,
            .le => cmp == .lt or cmp == .eq,
        };
    }

    fn getConditionValue(expr: []const u8, frame: ?*FrameInfo) []const u8 {
        // Try to get from frame locals
        if (frame) |f| {
            if (f.locals.get(expr)) |val| {
                return val;
            }
        }

        // Strip quotes for string literals
        if (expr.len >= 2) {
            if ((expr[0] == '"' and expr[expr.len - 1] == '"') or
                (expr[0] == '\'' and expr[expr.len - 1] == '\''))
            {
                return expr[1 .. expr.len - 1];
            }
        }

        // Return as literal
        return expr;
    }
};

/// Check if breakpoint matches function
pub fn checkfuncname(bp: *const Breakpoint, frame: *const FrameInfo) bool {
    if (bp.funcname) |funcname| {
        return std.mem.eql(u8, funcname, frame.function);
    }
    return true; // No funcname restriction
}

// ============================================================================
// Tests
// ============================================================================

test "Breakpoint init" {
    const bp = Breakpoint.init(1, "test.py", 10, false, null, null);
    try std.testing.expectEqual(@as(usize, 1), bp.number);
    try std.testing.expectEqualStrings("test.py", bp.file);
    try std.testing.expectEqual(@as(usize, 10), bp.line);
    try std.testing.expect(bp.enabled);
}

test "Breakpoint enable/disable" {
    var bp = Breakpoint.init(1, "test.py", 10, false, null, null);

    bp.disable();
    try std.testing.expect(!bp.enabled);

    bp.enable();
    try std.testing.expect(bp.enabled);
}

test "checkfuncname" {
    var frame = FrameInfo{
        .filename = "test.py",
        .lineno = 10,
        .function = "myfunction",
        .code_context = null,
        .locals = null,
    };

    // No funcname restriction
    const bp1 = Breakpoint.init(1, "test.py", 10, false, null, null);
    try std.testing.expect(checkfuncname(&bp1, &frame));

    // Matching funcname
    const bp2 = Breakpoint.init(2, "test.py", 10, false, null, "myfunction");
    try std.testing.expect(checkfuncname(&bp2, &frame));

    // Non-matching funcname
    const bp3 = Breakpoint.init(3, "test.py", 10, false, null, "otherfunction");
    try std.testing.expect(!checkfuncname(&bp3, &frame));
}

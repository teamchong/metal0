/// AST Unparse Expressions
/// Expression unparsing methods

const std = @import("std");
const core = @import("core.zig");
const Unparser = core.Unparser;
const types = @import("types.zig");
const Precedence = types.Precedence;
const Keyword = types.Keyword;
const operators = @import("operators.zig");
const BinaryOp = operators.BinaryOp;
const UnaryOp = operators.UnaryOp;
const CmpOp = operators.CmpOp;
const BoolOp = operators.BoolOp;

// ============================================================================
// Operator Expression Methods
// ============================================================================

/// Unparse a binary operation
pub fn unparseBinaryOp(self: *Unparser, op: BinaryOp, left: []const u8, right: []const u8, level: Precedence) !void {
    const pr = op.getPrecedence();
    const rassoc = op.isRightAssoc();

    if (@intFromEnum(level) > @intFromEnum(pr)) {
        try self.appendChar('(');
    }

    // Left operand
    try self.appendStr(left);

    // Operator
    try self.appendStr(op.getString());

    // Right operand
    _ = rassoc;
    try self.appendStr(right);

    if (@intFromEnum(level) > @intFromEnum(pr)) {
        try self.appendChar(')');
    }
}

/// Unparse a unary operation
pub fn unparseUnaryOp(self: *Unparser, op: UnaryOp, operand: []const u8) !void {
    try self.appendStr(op.getString());
    try self.appendStr(operand);
}

/// Unparse a comparison
pub fn unparseComparison(self: *Unparser, ops: []const CmpOp, comparators: []const []const u8) !void {
    for (ops, 0..) |op, i| {
        try self.appendStr(op.getString());
        if (i < comparators.len) {
            try self.appendStr(comparators[i]);
        }
    }
}

/// Unparse a boolean operation
pub fn unparseBoolOp(self: *Unparser, op: BoolOp, values: []const []const u8, level: Precedence) !void {
    const pr = op.getPrecedence();

    if (@intFromEnum(level) > @intFromEnum(pr)) {
        try self.appendChar('(');
    }

    for (values, 0..) |value, i| {
        if (i > 0) {
            try self.appendStr(op.getString());
        }
        try self.appendStr(value);
    }

    if (@intFromEnum(level) > @intFromEnum(pr)) {
        try self.appendChar(')');
    }
}

// ============================================================================
// Container Expression Methods
// ============================================================================

/// Unparse a list
pub fn unparseList(self: *Unparser, elements: []const []const u8) !void {
    try self.appendChar('[');
    for (elements, 0..) |elem, i| {
        if (i > 0) {
            try self.appendStr(", ");
        }
        try self.appendStr(elem);
    }
    try self.appendChar(']');
}

/// Unparse a tuple
pub fn unparseTuple(self: *Unparser, elements: []const []const u8) !void {
    try self.appendChar('(');
    for (elements, 0..) |elem, i| {
        if (i > 0) {
            try self.appendStr(", ");
        }
        try self.appendStr(elem);
    }
    // Trailing comma for single-element tuple
    if (elements.len == 1) {
        try self.appendChar(',');
    }
    try self.appendChar(')');
}

/// Unparse a set
pub fn unparseSet(self: *Unparser, elements: []const []const u8) !void {
    if (elements.len == 0) {
        try self.appendStr("set()");
        return;
    }
    try self.appendChar('{');
    for (elements, 0..) |elem, i| {
        if (i > 0) {
            try self.appendStr(", ");
        }
        try self.appendStr(elem);
    }
    try self.appendChar('}');
}

/// Unparse a dict
pub fn unparseDict(self: *Unparser, keys: []const ?[]const u8, values: []const []const u8) !void {
    try self.appendChar('{');
    for (keys, 0..) |key_opt, i| {
        if (i > 0) {
            try self.appendStr(", ");
        }
        if (key_opt) |key| {
            try self.appendStr(key);
            try self.appendStr(": ");
        } else {
            try self.appendStr("**");
        }
        if (i < values.len) {
            try self.appendStr(values[i]);
        }
    }
    try self.appendChar('}');
}

// ============================================================================
// Access Expression Methods
// ============================================================================

/// Unparse an attribute access
pub fn unparseAttribute(self: *Unparser, value: []const u8, attr: []const u8) !void {
    try self.appendStr(value);
    try self.appendChar('.');
    try self.appendStr(attr);
}

/// Unparse a subscript
pub fn unparseSubscript(self: *Unparser, value: []const u8, slice: []const u8) !void {
    try self.appendStr(value);
    try self.appendChar('[');
    try self.appendStr(slice);
    try self.appendChar(']');
}

/// Unparse a slice
pub fn unparseSlice(self: *Unparser, lower: ?[]const u8, upper: ?[]const u8, step: ?[]const u8) !void {
    if (lower) |l| {
        try self.appendStr(l);
    }
    try self.appendChar(':');
    if (upper) |u| {
        try self.appendStr(u);
    }
    if (step) |s| {
        try self.appendChar(':');
        try self.appendStr(s);
    }
}

// ============================================================================
// Call and Control Flow Expression Methods
// ============================================================================

/// Unparse a function call
pub fn unparseCall(self: *Unparser, func: []const u8, args: []const []const u8, keywords: []const Keyword) !void {
    try self.appendStr(func);
    try self.appendChar('(');

    var first = true;
    for (args) |arg| {
        if (!first) {
            try self.appendStr(", ");
        }
        try self.appendStr(arg);
        first = false;
    }

    for (keywords) |kw| {
        if (!first) {
            try self.appendStr(", ");
        }
        if (kw.name) |name| {
            try self.appendStr(name);
            try self.appendChar('=');
        } else {
            try self.appendStr("**");
        }
        try self.appendStr(kw.value);
        first = false;
    }

    try self.appendChar(')');
}

/// Unparse a conditional expression
pub fn unparseIfExp(self: *Unparser, test_expr: []const u8, body: []const u8, else_body: []const u8, level: Precedence) !void {
    if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
        try self.appendChar('(');
    }

    try self.appendStr(body);
    try self.appendStr(" if ");
    try self.appendStr(test_expr);
    try self.appendStr(" else ");
    try self.appendStr(else_body);

    if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
        try self.appendChar(')');
    }
}

/// Unparse a lambda expression
pub fn unparseLambda(self: *Unparser, args: []const u8, body: []const u8, level: Precedence) !void {
    if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
        try self.appendChar('(');
    }

    try self.appendStr("lambda ");
    try self.appendStr(args);
    try self.appendStr(": ");
    try self.appendStr(body);

    if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
        try self.appendChar(')');
    }
}

// ============================================================================
// Special Expression Methods
// ============================================================================

/// Unparse a starred expression
pub fn unparseStarred(self: *Unparser, value: []const u8) !void {
    try self.appendChar('*');
    try self.appendStr(value);
}

/// Unparse a named expression (walrus operator)
pub fn unparseNamedExpr(self: *Unparser, target: []const u8, value: []const u8) !void {
    try self.appendChar('(');
    try self.appendStr(target);
    try self.appendStr(" := ");
    try self.appendStr(value);
    try self.appendChar(')');
}

/// Unparse an await expression
pub fn unparseAwait(self: *Unparser, value: []const u8) !void {
    try self.appendStr("await ");
    try self.appendStr(value);
}

/// Unparse a yield expression
pub fn unparseYield(self: *Unparser, value: ?[]const u8) !void {
    try self.appendStr("(yield");
    if (value) |v| {
        try self.appendChar(' ');
        try self.appendStr(v);
    }
    try self.appendChar(')');
}

/// Unparse a yield from expression
pub fn unparseYieldFrom(self: *Unparser, value: []const u8) !void {
    try self.appendStr("(yield from ");
    try self.appendStr(value);
    try self.appendChar(')');
}

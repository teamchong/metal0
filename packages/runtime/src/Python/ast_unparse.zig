/// ast_unparse - AST to Source Code
/// Mirrors cpython/Python/ast_unparse.c
///
/// Limited unparser for converting AST back to string representation,
/// primarily used for annotations during compilation.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Priority Levels for Operator Precedence
// ============================================================================

/// Operator precedence levels for proper parenthesization
pub const Precedence = enum(u8) {
    PR_TUPLE = 0,
    PR_TEST = 1, // 'if'-'else', 'lambda'
    PR_OR = 2, // 'or'
    PR_AND = 3, // 'and'
    PR_NOT = 4, // 'not'
    PR_CMP = 5, // comparisons
    PR_EXPR = 6,
    PR_BOR = 6, // '|' (same as EXPR)
    PR_BXOR = 7, // '^'
    PR_BAND = 8, // '&'
    PR_SHIFT = 9, // '<<', '>>'
    PR_ARITH = 10, // '+', '-'
    PR_TERM = 11, // '*', '@', '/', '%', '//'
    PR_FACTOR = 12, // unary '+', '-', '~'
    PR_POWER = 13, // '**'
    PR_AWAIT = 14, // 'await'
    PR_ATOM = 15,
};

// ============================================================================
// AST Node Types (minimal for unparsing)
// ============================================================================

/// Expression kinds
pub const ExprKind = enum {
    // Literals
    constant,
    name,

    // Operations
    bool_op,
    bin_op,
    unary_op,
    compare,

    // Containers
    list,
    tuple,
    dict,
    set,

    // Comprehensions
    list_comp,
    set_comp,
    dict_comp,
    generator,

    // Subscripts and attributes
    attribute,
    subscript,
    slice,

    // Calls
    call,

    // Conditionals
    if_exp,
    lambda,

    // Special
    starred,
    named_expr, // := walrus operator
    await,
    yield,
    yield_from,

    // f-strings
    formatted_value,
    joined_str,
};

/// Binary operators
pub const BinaryOp = enum {
    add,
    sub,
    mult,
    mat_mult,
    div,
    mod,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
    floor_div,
    pow,

    pub fn getString(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => " + ",
            .sub => " - ",
            .mult => " * ",
            .mat_mult => " @ ",
            .div => " / ",
            .mod => " % ",
            .lshift => " << ",
            .rshift => " >> ",
            .bit_or => " | ",
            .bit_xor => " ^ ",
            .bit_and => " & ",
            .floor_div => " // ",
            .pow => " ** ",
        };
    }

    pub fn getPrecedence(self: BinaryOp) Precedence {
        return switch (self) {
            .add, .sub => .PR_ARITH,
            .mult, .mat_mult, .div, .mod, .floor_div => .PR_TERM,
            .lshift, .rshift => .PR_SHIFT,
            .bit_or => .PR_BOR,
            .bit_xor => .PR_BXOR,
            .bit_and => .PR_BAND,
            .pow => .PR_POWER,
        };
    }

    pub fn isRightAssoc(self: BinaryOp) bool {
        return self == .pow;
    }
};

/// Unary operators
pub const UnaryOp = enum {
    invert,
    not_op,
    uadd,
    usub,

    pub fn getString(self: UnaryOp) []const u8 {
        return switch (self) {
            .invert => "~",
            .not_op => "not ",
            .uadd => "+",
            .usub => "-",
        };
    }
};

/// Comparison operators
pub const CmpOp = enum {
    eq,
    not_eq,
    lt,
    lt_e,
    gt,
    gt_e,
    is,
    is_not,
    in_op,
    not_in,

    pub fn getString(self: CmpOp) []const u8 {
        return switch (self) {
            .eq => " == ",
            .not_eq => " != ",
            .lt => " < ",
            .lt_e => " <= ",
            .gt => " > ",
            .gt_e => " >= ",
            .is => " is ",
            .is_not => " is not ",
            .in_op => " in ",
            .not_in => " not in ",
        };
    }
};

/// Boolean operators
pub const BoolOp = enum {
    and_op,
    or_op,

    pub fn getString(self: BoolOp) []const u8 {
        return switch (self) {
            .and_op => " and ",
            .or_op => " or ",
        };
    }

    pub fn getPrecedence(self: BoolOp) Precedence {
        return switch (self) {
            .and_op => .PR_AND,
            .or_op => .PR_OR,
        };
    }
};

// ============================================================================
// AST Unparser
// ============================================================================

/// AST Unparser state
pub const Unparser = struct {
    const Self = @This();

    allocator: Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Reset buffer for reuse
    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Get the result string
    pub fn getResult(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Append a character
    pub fn appendChar(self: *Self, ch: u8) !void {
        try self.buffer.append(ch);
    }

    /// Append a string
    pub fn appendStr(self: *Self, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }

    /// Append string representation of an integer
    pub fn appendInt(self: *Self, value: i64) !void {
        var buf: [32]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.appendStr(str);
    }

    /// Append string representation of a float
    pub fn appendFloat(self: *Self, value: f64) !void {
        var buf: [64]u8 = undefined;

        // Handle infinity
        if (std.math.isInf(value)) {
            if (value < 0) {
                try self.appendStr("-1e309");
            } else {
                try self.appendStr("1e309");
            }
            return;
        }

        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.appendStr(str);
    }

    /// Append a repr-style string
    pub fn appendRepr(self: *Self, str: []const u8) !void {
        try self.appendChar('\'');
        for (str) |c| {
            switch (c) {
                '\'' => try self.appendStr("\\'"),
                '\\' => try self.appendStr("\\\\"),
                '\n' => try self.appendStr("\\n"),
                '\r' => try self.appendStr("\\r"),
                '\t' => try self.appendStr("\\t"),
                else => {
                    if (c < 32 or c >= 127) {
                        var buf: [8]u8 = undefined;
                        const hex = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{c}) catch return error.FormatError;
                        try self.appendStr(hex);
                    } else {
                        try self.appendChar(c);
                    }
                },
            }
        }
        try self.appendChar('\'');
    }

    /// Unparse a constant value
    pub fn unparseConstant(self: *Self, value: ConstantValue) !void {
        switch (value) {
            .none => try self.appendStr("None"),
            .true_val => try self.appendStr("True"),
            .false_val => try self.appendStr("False"),
            .ellipsis => try self.appendStr("..."),
            .int_val => |v| try self.appendInt(v),
            .float_val => |v| try self.appendFloat(v),
            .str_val => |v| try self.appendRepr(v),
            .bytes_val => |v| {
                try self.appendStr("b");
                try self.appendRepr(v);
            },
        }
    }

    /// Unparse a name
    pub fn unparseName(self: *Self, name: []const u8) !void {
        try self.appendStr(name);
    }

    /// Unparse a binary operation
    pub fn unparseBinaryOp(self: *Self, op: BinaryOp, left: []const u8, right: []const u8, level: Precedence) !void {
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
    pub fn unparseUnaryOp(self: *Self, op: UnaryOp, operand: []const u8) !void {
        try self.appendStr(op.getString());
        try self.appendStr(operand);
    }

    /// Unparse a comparison
    pub fn unparseComparison(self: *Self, ops: []const CmpOp, comparators: []const []const u8) !void {
        for (ops, 0..) |op, i| {
            try self.appendStr(op.getString());
            if (i < comparators.len) {
                try self.appendStr(comparators[i]);
            }
        }
    }

    /// Unparse a boolean operation
    pub fn unparseBoolOp(self: *Self, op: BoolOp, values: []const []const u8, level: Precedence) !void {
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

    /// Unparse a list
    pub fn unparseList(self: *Self, elements: []const []const u8) !void {
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
    pub fn unparseTuple(self: *Self, elements: []const []const u8) !void {
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
    pub fn unparseSet(self: *Self, elements: []const []const u8) !void {
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
    pub fn unparseDict(self: *Self, keys: []const ?[]const u8, values: []const []const u8) !void {
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

    /// Unparse an attribute access
    pub fn unparseAttribute(self: *Self, value: []const u8, attr: []const u8) !void {
        try self.appendStr(value);
        try self.appendChar('.');
        try self.appendStr(attr);
    }

    /// Unparse a subscript
    pub fn unparseSubscript(self: *Self, value: []const u8, slice: []const u8) !void {
        try self.appendStr(value);
        try self.appendChar('[');
        try self.appendStr(slice);
        try self.appendChar(']');
    }

    /// Unparse a slice
    pub fn unparseSlice(self: *Self, lower: ?[]const u8, upper: ?[]const u8, step: ?[]const u8) !void {
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

    /// Unparse a function call
    pub fn unparseCall(self: *Self, func: []const u8, args: []const []const u8, keywords: []const Keyword) !void {
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
    pub fn unparseIfExp(self: *Self, test_expr: []const u8, body: []const u8, orelse: []const u8, level: Precedence) !void {
        if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
            try self.appendChar('(');
        }

        try self.appendStr(body);
        try self.appendStr(" if ");
        try self.appendStr(test_expr);
        try self.appendStr(" else ");
        try self.appendStr(orelse);

        if (@intFromEnum(level) > @intFromEnum(Precedence.PR_TEST)) {
            try self.appendChar(')');
        }
    }

    /// Unparse a lambda expression
    pub fn unparseLambda(self: *Self, args: []const u8, body: []const u8, level: Precedence) !void {
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

    /// Unparse a starred expression
    pub fn unparseStarred(self: *Self, value: []const u8) !void {
        try self.appendChar('*');
        try self.appendStr(value);
    }

    /// Unparse a named expression (walrus operator)
    pub fn unparseNamedExpr(self: *Self, target: []const u8, value: []const u8) !void {
        try self.appendChar('(');
        try self.appendStr(target);
        try self.appendStr(" := ");
        try self.appendStr(value);
        try self.appendChar(')');
    }

    /// Unparse an await expression
    pub fn unparseAwait(self: *Self, value: []const u8) !void {
        try self.appendStr("await ");
        try self.appendStr(value);
    }

    /// Unparse a yield expression
    pub fn unparseYield(self: *Self, value: ?[]const u8) !void {
        try self.appendStr("(yield");
        if (value) |v| {
            try self.appendChar(' ');
            try self.appendStr(v);
        }
        try self.appendChar(')');
    }

    /// Unparse a yield from expression
    pub fn unparseYieldFrom(self: *Self, value: []const u8) !void {
        try self.appendStr("(yield from ");
        try self.appendStr(value);
        try self.appendChar(')');
    }
};

/// Keyword argument
pub const Keyword = struct {
    name: ?[]const u8, // null for **kwargs
    value: []const u8,
};

/// Constant value types
pub const ConstantValue = union(enum) {
    none: void,
    true_val: void,
    false_val: void,
    ellipsis: void,
    int_val: i64,
    float_val: f64,
    str_val: []const u8,
    bytes_val: []const u8,
};

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the ast_unparse module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "unparse constant" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseConstant(.none);
    try std.testing.expectEqualStrings("None", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.{ .int_val = 42 });
    try std.testing.expectEqualStrings("42", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.true_val);
    try std.testing.expectEqualStrings("True", unparser.getResult());
}

test "unparse string repr" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseConstant(.{ .str_val = "hello" });
    try std.testing.expectEqualStrings("'hello'", unparser.getResult());

    unparser.reset();
    try unparser.unparseConstant(.{ .str_val = "it's" });
    try std.testing.expectEqualStrings("'it\\'s'", unparser.getResult());
}

test "unparse list" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    const elements = [_][]const u8{ "1", "2", "3" };
    try unparser.unparseList(&elements);
    try std.testing.expectEqualStrings("[1, 2, 3]", unparser.getResult());
}

test "unparse tuple" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    const single = [_][]const u8{"1"};
    try unparser.unparseTuple(&single);
    try std.testing.expectEqualStrings("(1,)", unparser.getResult());

    unparser.reset();
    const multi = [_][]const u8{ "1", "2" };
    try unparser.unparseTuple(&multi);
    try std.testing.expectEqualStrings("(1, 2)", unparser.getResult());
}

test "unparse set" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    const empty = [_][]const u8{};
    try unparser.unparseSet(&empty);
    try std.testing.expectEqualStrings("set()", unparser.getResult());

    unparser.reset();
    const elements = [_][]const u8{ "1", "2" };
    try unparser.unparseSet(&elements);
    try std.testing.expectEqualStrings("{1, 2}", unparser.getResult());
}

test "unparse attribute" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseAttribute("obj", "attr");
    try std.testing.expectEqualStrings("obj.attr", unparser.getResult());
}

test "unparse subscript" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseSubscript("lst", "0");
    try std.testing.expectEqualStrings("lst[0]", unparser.getResult());
}

test "unparse slice" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseSlice("1", "10", "2");
    try std.testing.expectEqualStrings("1:10:2", unparser.getResult());

    unparser.reset();
    try unparser.unparseSlice(null, "10", null);
    try std.testing.expectEqualStrings(":10", unparser.getResult());
}

test "unparse call" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    const args = [_][]const u8{ "1", "2" };
    const keywords = [_]Keyword{.{ .name = "x", .value = "3" }};
    try unparser.unparseCall("func", &args, &keywords);
    try std.testing.expectEqualStrings("func(1, 2, x=3)", unparser.getResult());
}

test "unparse if expression" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseIfExp("cond", "a", "b", .PR_TUPLE);
    try std.testing.expectEqualStrings("a if cond else b", unparser.getResult());
}

test "unparse walrus operator" {
    const allocator = std.testing.allocator;

    var unparser = Unparser.init(allocator);
    defer unparser.deinit();

    try unparser.unparseNamedExpr("x", "10");
    try std.testing.expectEqualStrings("(x := 10)", unparser.getResult());
}

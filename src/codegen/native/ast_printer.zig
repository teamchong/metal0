/// AST Printer - Converts AST nodes back to valid Python source code
/// Used for VM fallback: when native codegen can't handle something,
/// reconstruct Python source and pass to runtime.eval()
const std = @import("std");
const analysis_ast = @import("analysis.ast");
const ast = struct {
    // Re-export types from analysis.ast for compatibility
    pub const Node = analysis_ast.Node;
    pub const Operator = analysis_ast.Operator;
    pub const CompareOp = analysis_ast.CompareOp;
    pub const UnaryOperator = analysis_ast.UnaryOperator;
    pub const Arg = analysis_ast.Arg;
    pub const FString = analysis_ast.FString;
};

/// Error type for AST printing operations
pub const PrintError = error{OutOfMemory, UnsupportedNodeType};

pub const AstPrinter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) AstPrinter {
        return .{
            .allocator = allocator,
            .output = .{},
        };
    }

    pub fn deinit(self: *AstPrinter) void {
        self.output.deinit(self.allocator);
    }

    /// Convert an AST node to Python source string
    /// Caller owns returned memory
    pub fn print(self: *AstPrinter, node: ast.Node) ![]const u8 {
        self.output.clearRetainingCapacity();
        try self.printNode(node);
        return try self.output.toOwnedSlice(self.allocator);
    }

    /// Print node to internal buffer (doesn't allocate result)
    fn printNode(self: *AstPrinter, node: ast.Node) PrintError!void {
        switch (node) {
            // P0: Basic expressions
            .constant => |c| try self.printConstant(c),
            .name => |n| try self.appendStr(n.id),
            .binop => |b| try self.printBinOp(b),
            .unaryop => |u| try self.printUnaryOp(u),
            .compare => |c| try self.printCompare(c),
            .boolop => |b| try self.printBoolOp(b),
            .call => |c| try self.printCall(c),
            .attribute => |a| try self.printAttribute(a),
            .subscript => |s| try self.printSubscript(s),
            .list => |l| try self.printList(l),
            .tuple => |t| try self.printTuple(t),
            .dict => |d| try self.printDict(d),
            .set => |s| try self.printSet(s),

            // P1: Lambda and comprehensions
            .lambda => |l| try self.printLambda(l),
            .listcomp => |l| try self.printListComp(l),
            .dictcomp => |d| try self.printDictComp(d),
            .genexp => |g| try self.printGenExp(g),
            .if_expr => |i| try self.printIfExpr(i),
            .named_expr => |n| try self.printNamedExpr(n),

            // P2: Advanced
            .starred => |s| try self.printStarred(s),
            .double_starred => |d| try self.printDoubleStarred(d),
            .slice_expr => |s| try self.printSliceRange(s),
            .fstring => |f| try self.printFString(f),
            .await_expr => |a| try self.printAwait(a),
            .ellipsis_literal => try self.appendStr("..."),

            // Statements (for completeness - usually not needed for expressions)
            .assign => |a| try self.printAssign(a),
            .aug_assign => |a| try self.printAugAssign(a),
            .expr_stmt => |e| try self.printNode(e.value.*),
            .return_stmt => |r| try self.printReturn(r),
            .pass => try self.appendStr("pass"),
            .break_stmt => try self.appendStr("break"),
            .continue_stmt => try self.appendStr("continue"),

            // Skip complex statements for now - not usually needed for expression fallback
            else => return error.UnsupportedNodeType,
        }
    }

    // ========================================================================
    // P0: Basic expressions
    // ========================================================================

    fn printConstant(self: *AstPrinter, c: ast.Node.Constant) !void {
        switch (c.value) {
            .int => |i| {
                var buf: [32]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "0";
                try self.appendStr(slice);
            },
            .bigint => |s| try self.appendStr(s),
            .float => |f| {
                var buf: [64]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "0.0";
                try self.appendStr(slice);
                // Ensure it looks like a float (has decimal point)
                if (std.mem.indexOf(u8, slice, ".") == null and
                    std.mem.indexOf(u8, slice, "e") == null and
                    std.mem.indexOf(u8, slice, "E") == null)
                {
                    try self.appendStr(".0");
                }
            },
            .string => |s| {
                try self.append('"');
                try self.escapeString(s);
                try self.append('"');
            },
            .bytes => |b| {
                try self.appendStr("b\"");
                try self.escapeBytes(b);
                try self.append('"');
            },
            .bool => |b| try self.appendStr(if (b) "True" else "False"),
            .none => try self.appendStr("None"),
            .complex => |imag| {
                var buf: [64]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}j", .{imag}) catch "0j";
                try self.appendStr(slice);
            },
        }
    }

    fn printBinOp(self: *AstPrinter, b: ast.Node.BinOp) !void {
        try self.append('(');
        try self.printNode(b.left.*);
        try self.appendStr(operatorToString(b.op));
        try self.printNode(b.right.*);
        try self.append(')');
    }

    fn printUnaryOp(self: *AstPrinter, u: ast.Node.UnaryOp) !void {
        try self.appendStr(unaryOpToString(u.op));
        const needs_parens = switch (u.operand.*) {
            .binop, .compare, .boolop => true,
            else => false,
        };
        if (needs_parens) try self.append('(');
        try self.printNode(u.operand.*);
        if (needs_parens) try self.append(')');
    }

    fn printCompare(self: *AstPrinter, c: ast.Node.Compare) !void {
        try self.append('(');
        try self.printNode(c.left.*);
        for (c.ops, c.comparators) |op, cmp| {
            try self.appendStr(compareOpToString(op));
            try self.printNode(cmp);
        }
        try self.append(')');
    }

    fn printBoolOp(self: *AstPrinter, b: ast.Node.BoolOp) !void {
        try self.append('(');
        const op_str = switch (b.op) {
            .And => " and ",
            .Or => " or ",
        };
        for (b.values, 0..) |val, i| {
            if (i > 0) try self.appendStr(op_str);
            try self.printNode(val);
        }
        try self.append(')');
    }

    fn printCall(self: *AstPrinter, c: ast.Node.Call) !void {
        try self.printNode(c.func.*);
        try self.append('(');

        var first = true;
        for (c.args) |arg| {
            if (!first) try self.appendStr(", ");
            first = false;
            try self.printNode(arg);
        }

        for (c.keyword_args) |kwarg| {
            if (!first) try self.appendStr(", ");
            first = false;
            try self.appendStr(kwarg.name);
            try self.append('=');
            try self.printNode(kwarg.value);
        }

        try self.append(')');
    }

    fn printAttribute(self: *AstPrinter, a: ast.Node.Attribute) !void {
        try self.printNode(a.value.*);
        try self.append('.');
        try self.appendStr(a.attr);
    }

    fn printSubscript(self: *AstPrinter, s: ast.Node.Subscript) !void {
        try self.printNode(s.value.*);
        try self.append('[');
        switch (s.slice) {
            .index => |idx| try self.printNode(idx.*),
            .slice => |sl| try self.printSliceRange(sl),
        }
        try self.append(']');
    }

    fn printList(self: *AstPrinter, l: ast.Node.List) !void {
        try self.append('[');
        for (l.elts, 0..) |elt, i| {
            if (i > 0) try self.appendStr(", ");
            try self.printNode(elt);
        }
        try self.append(']');
    }

    fn printTuple(self: *AstPrinter, t: ast.Node.Tuple) !void {
        try self.append('(');
        for (t.elts, 0..) |elt, i| {
            if (i > 0) try self.appendStr(", ");
            try self.printNode(elt);
        }
        // Single element tuple needs trailing comma
        if (t.elts.len == 1) try self.append(',');
        try self.append(')');
    }

    fn printDict(self: *AstPrinter, d: ast.Node.Dict) !void {
        try self.append('{');
        for (d.keys, d.values, 0..) |key, val, i| {
            if (i > 0) try self.appendStr(", ");
            try self.printNode(key);
            try self.appendStr(": ");
            try self.printNode(val);
        }
        try self.append('}');
    }

    fn printSet(self: *AstPrinter, s: ast.Node.Set) !void {
        try self.append('{');
        for (s.elts, 0..) |elt, i| {
            if (i > 0) try self.appendStr(", ");
            try self.printNode(elt);
        }
        try self.append('}');
    }

    // ========================================================================
    // P1: Lambda and comprehensions
    // ========================================================================

    fn printLambda(self: *AstPrinter, l: ast.Node.Lambda) !void {
        try self.appendStr("lambda");
        if (l.args.len > 0) {
            try self.append(' ');
            for (l.args, 0..) |arg, i| {
                if (i > 0) try self.appendStr(", ");
                try self.appendStr(arg.name);
                if (arg.default) |def| {
                    try self.append('=');
                    try self.printNode(def.*);
                }
            }
        }
        try self.appendStr(": ");
        try self.printNode(l.body.*);
    }

    fn printListComp(self: *AstPrinter, l: ast.Node.ListComp) !void {
        try self.append('[');
        try self.printNode(l.elt.*);
        for (l.generators) |gen| {
            try self.printComprehension(gen);
        }
        try self.append(']');
    }

    fn printDictComp(self: *AstPrinter, d: ast.Node.DictComp) !void {
        try self.append('{');
        try self.printNode(d.key.*);
        try self.appendStr(": ");
        try self.printNode(d.value.*);
        for (d.generators) |gen| {
            try self.printComprehension(gen);
        }
        try self.append('}');
    }

    fn printGenExp(self: *AstPrinter, g: ast.Node.GenExp) !void {
        try self.append('(');
        try self.printNode(g.elt.*);
        for (g.generators) |gen| {
            try self.printComprehension(gen);
        }
        try self.append(')');
    }

    fn printComprehension(self: *AstPrinter, c: ast.Node.Comprehension) !void {
        try self.appendStr(" for ");
        try self.printNode(c.target.*);
        try self.appendStr(" in ");
        try self.printNode(c.iter.*);
        for (c.ifs) |cond| {
            try self.appendStr(" if ");
            try self.printNode(cond);
        }
    }

    fn printIfExpr(self: *AstPrinter, i: ast.Node.IfExpr) !void {
        try self.append('(');
        try self.printNode(i.body.*);
        try self.appendStr(" if ");
        try self.printNode(i.condition.*);
        try self.appendStr(" else ");
        try self.printNode(i.orelse_value.*);
        try self.append(')');
    }

    fn printNamedExpr(self: *AstPrinter, n: ast.Node.NamedExpr) !void {
        try self.append('(');
        try self.printNode(n.target.*);
        try self.appendStr(" := ");
        try self.printNode(n.value.*);
        try self.append(')');
    }

    // ========================================================================
    // P2: Advanced expressions
    // ========================================================================

    fn printStarred(self: *AstPrinter, s: ast.Node.Starred) !void {
        try self.append('*');
        try self.printNode(s.value.*);
    }

    fn printDoubleStarred(self: *AstPrinter, d: ast.Node.DoubleStarred) !void {
        try self.appendStr("**");
        try self.printNode(d.value.*);
    }

    fn printSliceRange(self: *AstPrinter, s: ast.Node.SliceRange) !void {
        if (s.lower) |l| try self.printNode(l.*);
        try self.append(':');
        if (s.upper) |u| try self.printNode(u.*);
        if (s.step) |st| {
            try self.append(':');
            try self.printNode(st.*);
        }
    }

    fn printFString(self: *AstPrinter, f: ast.FString) PrintError!void {
        try self.appendStr("f\"");
        for (f.parts) |part| {
            switch (part) {
                .literal => |lit| try self.escapeString(lit),
                .expr => |e| {
                    try self.append('{');
                    if (e.debug_text) |debug| try self.appendStr(debug);
                    try self.printNode(e.node.*);
                    try self.append('}');
                },
                .format_expr => |fe| {
                    try self.append('{');
                    if (fe.debug_text) |debug| try self.appendStr(debug);
                    try self.printNode(fe.expr.*);
                    if (fe.conversion) |conv| {
                        try self.append('!');
                        try self.append(conv);
                    }
                    if (fe.format_spec.len > 0) {
                        try self.append(':');
                        try self.appendStr(fe.format_spec);
                    }
                    try self.append('}');
                },
                .conv_expr => |ce| {
                    try self.append('{');
                    if (ce.debug_text) |debug| try self.appendStr(debug);
                    try self.printNode(ce.expr.*);
                    try self.append('!');
                    try self.append(ce.conversion);
                    try self.append('}');
                },
            }
        }
        try self.append('"');
    }

    fn printAwait(self: *AstPrinter, a: ast.Node.AwaitExpr) !void {
        try self.appendStr("await ");
        try self.printNode(a.value.*);
    }

    // ========================================================================
    // Statement helpers (minimal, for completeness)
    // ========================================================================

    fn printAssign(self: *AstPrinter, a: ast.Node.Assign) !void {
        for (a.targets, 0..) |target, i| {
            if (i > 0) try self.appendStr(" = ");
            try self.printNode(target);
        }
        try self.appendStr(" = ");
        try self.printNode(a.value.*);
    }

    fn printAugAssign(self: *AstPrinter, a: ast.Node.AugAssign) !void {
        try self.printNode(a.target.*);
        try self.append(' ');
        try self.appendStr(operatorToString(a.op));
        try self.appendStr("= ");
        try self.printNode(a.value.*);
    }

    fn printReturn(self: *AstPrinter, r: ast.Node.Return) !void {
        try self.appendStr("return");
        if (r.value) |v| {
            try self.append(' ');
            try self.printNode(v.*);
        }
    }

    // ========================================================================
    // Helpers
    // ========================================================================

    fn append(self: *AstPrinter, c: u8) !void {
        try self.output.append(self.allocator, c);
    }

    fn appendStr(self: *AstPrinter, s: []const u8) !void {
        try self.output.appendSlice(self.allocator, s);
    }

    fn escapeString(self: *AstPrinter, s: []const u8) !void {
        for (s) |c| {
            switch (c) {
                '"' => try self.appendStr("\\\""),
                '\\' => try self.appendStr("\\\\"),
                '\n' => try self.appendStr("\\n"),
                '\r' => try self.appendStr("\\r"),
                '\t' => try self.appendStr("\\t"),
                else => try self.append(c),
            }
        }
    }

    fn escapeBytes(self: *AstPrinter, b: []const u8) !void {
        for (b) |c| {
            if (c >= 32 and c < 127 and c != '"' and c != '\\') {
                try self.append(c);
            } else {
                switch (c) {
                    '"' => try self.appendStr("\\\""),
                    '\\' => try self.appendStr("\\\\"),
                    '\n' => try self.appendStr("\\n"),
                    '\r' => try self.appendStr("\\r"),
                    '\t' => try self.appendStr("\\t"),
                    else => {
                        // \xHH format
                        try self.appendStr("\\x");
                        const hex = "0123456789abcdef";
                        try self.append(hex[c >> 4]);
                        try self.append(hex[c & 0x0f]);
                    },
                }
            }
        }
    }
};

// ============================================================================
// Operator string conversion
// ============================================================================

fn operatorToString(op: ast.Operator) []const u8 {
    return switch (op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .MatMul => " @ ",
        .Div => " / ",
        .FloorDiv => " // ",
        .Mod => " % ",
        .Pow => " ** ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        .LShift => " << ",
        .RShift => " >> ",
    };
}

fn compareOpToString(op: ast.CompareOp) []const u8 {
    return switch (op) {
        .Eq => " == ",
        .NotEq => " != ",
        .Lt => " < ",
        .LtEq => " <= ",
        .Gt => " > ",
        .GtEq => " >= ",
        .In => " in ",
        .NotIn => " not in ",
        .Is => " is ",
        .IsNot => " is not ",
    };
}

fn unaryOpToString(op: ast.UnaryOperator) []const u8 {
    return switch (op) {
        .Not => "not ",
        .UAdd => "+",
        .USub => "-",
        .Invert => "~",
    };
}

// ============================================================================
// Tests
// ============================================================================

test "print constant int" {
    var printer = AstPrinter.init(std.testing.allocator);
    defer printer.deinit();
    const result = try printer.print(.{ .constant = .{ .value = .{ .int = 42 } } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("42", result);
}

test "print constant string" {
    var printer = AstPrinter.init(std.testing.allocator);
    defer printer.deinit();
    const result = try printer.print(.{ .constant = .{ .value = .{ .string = "hello" } } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("\"hello\"", result);
}

test "print binary op" {
    var printer = AstPrinter.init(std.testing.allocator);
    defer printer.deinit();

    var left = ast.Node{ .constant = .{ .value = .{ .int = 1 } } };
    var right = ast.Node{ .constant = .{ .value = .{ .int = 2 } } };

    const result = try printer.print(.{ .binop = .{
        .left = &left,
        .op = .Add,
        .right = &right,
    } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("(1 + 2)", result);
}

test "print list" {
    var printer = AstPrinter.init(std.testing.allocator);
    defer printer.deinit();

    var elts = [_]ast.Node{
        .{ .constant = .{ .value = .{ .int = 1 } } },
        .{ .constant = .{ .value = .{ .int = 2 } } },
        .{ .constant = .{ .value = .{ .int = 3 } } },
    };

    const result = try printer.print(.{ .list = .{ .elts = &elts } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("[1, 2, 3]", result);
}

test "print lambda" {
    var printer = AstPrinter.init(std.testing.allocator);
    defer printer.deinit();

    var body = ast.Node{ .name = .{ .id = "x" } };
    var args = [_]ast.Arg{.{ .name = "x", .type_annotation = null, .default = null }};

    const result = try printer.print(.{ .lambda = .{
        .args = &args,
        .body = &body,
    } });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("lambda x: x", result);
}

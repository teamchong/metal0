/// Expression-level code generation
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const dispatch = @import("dispatch.zig");

/// Main expression dispatcher
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .constant => |c| try genConstant(self, c),
        .name => |n| try self.output.appendSlice(self.allocator, n.id),
        .binop => |b| try genBinOp(self, b),
        .unaryop => |u| try genUnaryOp(self, u),
        .compare => |c| try genCompare(self, c),
        .boolop => |b| try genBoolOp(self, b),
        .call => |c| try genCall(self, c),
        .list => |l| try genList(self, l),
        .dict => |d| try genDict(self, d),
        .subscript => |s| try genSubscript(self, s),
        else => {},
    }
}

/// Generate constant values (int, float, bool, string)
fn genConstant(self: *NativeCodegen, constant: ast.Node.Constant) CodegenError!void {
    switch (constant.value) {
        .int => try self.output.writer(self.allocator).print("{d}", .{constant.value.int}),
        .float => try self.output.writer(self.allocator).print("{d}", .{constant.value.float}),
        .bool => try self.output.appendSlice(self.allocator, if (constant.value.bool) "true" else "false"),
        .string => |s| {
            // Strip Python quotes
            const content = if (s.len >= 2) s[1 .. s.len - 1] else s;

            // Escape quotes and backslashes for Zig string literal
            try self.output.appendSlice(self.allocator, "\"");
            for (content) |c| {
                switch (c) {
                    '"' => try self.output.appendSlice(self.allocator, "\\\""),
                    '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                    '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                    '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                    '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                    else => try self.output.writer(self.allocator).print("{c}", .{c}),
                }
            }
            try self.output.appendSlice(self.allocator, "\"");
        },
    }
}

/// Generate binary operations (+, -, *, /, %, //)
fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    try self.output.appendSlice(self.allocator, "(");
    try genExpr(self, binop.left.*);

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        .Mod => " % ",
        .FloorDiv => " / ", // Zig doesn't distinguish
        else => " ? ",
    };
    try self.output.appendSlice(self.allocator, op_str);

    try genExpr(self, binop.right.*);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate unary operations (not, -)
fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const op_str = switch (unaryop.op) {
        .Not => "!",
        .USub => "-",
        else => "?",
    };
    try self.output.appendSlice(self.allocator, op_str);
    try genExpr(self, unaryop.operand.*);
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.type_inferrer.inferExpr(compare.left.*);

    for (compare.ops, 0..) |op, i| {
        const right_type = try self.type_inferrer.inferExpr(compare.comparators[i]);

        // Special handling for string comparisons
        if (left_type == .string and right_type == .string) {
            switch (op) {
                .Eq => {
                    try self.output.appendSlice(self.allocator, "std.mem.eql(u8, ");
                    try genExpr(self, compare.left.*);
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.output.appendSlice(self.allocator, ")");
                },
                .NotEq => {
                    try self.output.appendSlice(self.allocator, "!std.mem.eql(u8, ");
                    try genExpr(self, compare.left.*);
                    try self.output.appendSlice(self.allocator, ", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.output.appendSlice(self.allocator, ")");
                },
                else => {
                    // String comparison operators other than == and != not supported
                    try genExpr(self, compare.left.*);
                    const op_str = switch (op) {
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " ? ",
                    };
                    try self.output.appendSlice(self.allocator, op_str);
                    try genExpr(self, compare.comparators[i]);
                },
            }
        } else {
            // Regular comparisons for non-strings
            try genExpr(self, compare.left.*);
            const op_str = switch (op) {
                .Eq => " == ",
                .NotEq => " != ",
                .Lt => " < ",
                .LtEq => " <= ",
                .Gt => " > ",
                .GtEq => " >= ",
                else => " ? ",
            };
            try self.output.appendSlice(self.allocator, op_str);
            try genExpr(self, compare.comparators[i]);
        }
    }
}

/// Generate boolean operations (and, or)
fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
    const op_str = if (boolop.op == .And) " and " else " or ";

    for (boolop.values, 0..) |value, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, op_str);
        try genExpr(self, value);
    }
}

/// Generate function call - dispatches to specialized handlers or fallback
fn genCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!void {
    // Try to dispatch to specialized handler
    const dispatched = try dispatch.dispatchCall(self, call);
    if (dispatched) return;

    // Fallback: regular function call
    if (call.func.* == .name) {
        const func_name = call.func.name.id;
        try self.output.appendSlice(self.allocator, func_name);
        try self.output.appendSlice(self.allocator, "(");

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        try self.output.appendSlice(self.allocator, ")");
    }
}

/// Generate list literal or ArrayList
fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Empty lists become ArrayList for dynamic growth
    if (list.elts.len == 0) {
        try self.output.appendSlice(self.allocator, "std.ArrayList(i64){}");
        return;
    }

    // Non-empty lists are fixed arrays
    try self.output.appendSlice(self.allocator, "&[_]");

    // Infer element type
    const elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    try elem_type.toZigType(self.allocator, &self.output);

    try self.output.appendSlice(self.allocator, "{");

    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, elem);
    }

    try self.output.appendSlice(self.allocator, "}");
}

/// Generate dict literal as StringHashMap
fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Infer value type from first value
    const val_type = if (dict.values.len > 0)
        try self.type_inferrer.inferExpr(dict.values[0])
    else
        .unknown;

    // Generate: blk: {
    //   var map = std.StringHashMap(T).init(allocator);
    //   try map.put("key", value);
    //   break :blk map;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var map = std.StringHashMap(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, ").init(allocator);\n");

    // Add all key-value pairs
    for (dict.keys, dict.values) |key, value| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try map.put(");
        try genExpr(self, key);
        try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, value);
        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk map;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate array/dict subscript (a[b])
fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    try genExpr(self, subscript.value.*);
    try self.output.appendSlice(self.allocator, "[");

    switch (subscript.slice) {
        .index => |idx| try genExpr(self, idx.*),
        else => {}, // TODO: Slice support
    }

    try self.output.appendSlice(self.allocator, "]");
}

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
        .attribute => |a| try genAttribute(self, a),
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

/// Recursively collect all parts of a string concatenation chain
fn collectConcatParts(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);

        // Only flatten if this is string concatenation
        if (left_type == .string or right_type == .string) {
            try collectConcatParts(self, node.binop.left.*, parts);
            try collectConcatParts(self, node.binop.right.*, parts);
            return;
        }
    }

    // Base case: not a string concatenation binop, add to parts
    try parts.append(self.allocator, node);
}

/// Generate binary operations (+, -, *, /, %, //)
fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check if this is string concatenation
    if (binop.op == .Add) {
        const left_type = try self.type_inferrer.inferExpr(binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(binop.right.*);

        if (left_type == .string or right_type == .string) {
            // Flatten nested concatenations to avoid intermediate allocations
            var parts = std.ArrayList(ast.Node){};
            defer parts.deinit(self.allocator);

            try collectConcatParts(self, ast.Node{ .binop = binop }, &parts);

            // Generate single concat call with all parts
            try self.output.appendSlice(self.allocator, "try std.mem.concat(allocator, u8, &[_][]const u8{ ");
            for (parts.items, 0..) |part, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, part);
            }
            try self.output.appendSlice(self.allocator, " })");
            return;
        }
    }

    // Regular numeric operations
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

    // Handle method calls (obj.method())
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Generic method call: obj.method(args)
        try genExpr(self, attr.value.*);
        try self.output.appendSlice(self.allocator, ".");
        try self.output.appendSlice(self.allocator, attr.attr);
        try self.output.appendSlice(self.allocator, "(");

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Check for class instantiation (ClassName() -> ClassName.init())
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // If name starts with uppercase, it's a class constructor
        if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
            // Class instantiation: Counter(10) -> Counter.init(10)
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, ".init(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // Fallback: regular function call
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

/// Check if a node is a negative constant
fn isNegativeConstant(node: ast.Node) bool {
    if (node == .constant and node.constant.value == .int) {
        return node.constant.value.int < 0;
    }
    if (node == .unaryop and node.unaryop.op == .USub) {
        if (node.unaryop.operand.* == .constant and node.unaryop.operand.constant.value == .int) {
            return true;
        }
    }
    return false;
}

/// Generate a slice index, handling negative indices
/// If in_slice_context is true and we have __s available, convert negatives to __s.len - abs(index)
fn genSliceIndex(self: *NativeCodegen, node: ast.Node, in_slice_context: bool) CodegenError!void {
    if (!in_slice_context) {
        try genExpr(self, node);
        return;
    }

    // Check for negative constant or unary minus
    if (node == .constant and node.constant.value == .int and node.constant.value.int < 0) {
        // Negative constant: -2 becomes max(0, __s.len - 2) to prevent underflow
        const abs_val = if (node.constant.value.int < 0) -node.constant.value.int else node.constant.value.int;
        try self.output.writer(self.allocator).print("if (__s.len >= {d}) __s.len - {d} else 0", .{ abs_val, abs_val });
    } else if (node == .unaryop and node.unaryop.op == .USub) {
        // Unary minus: -x becomes saturating subtraction
        try self.output.appendSlice(self.allocator, "__s.len -| ");
        try genExpr(self, node.unaryop.operand.*);
    } else {
        // Positive index - use as-is
        try genExpr(self, node);
    }
}

/// Generate array/dict subscript (a[b])
fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    switch (subscript.slice) {
        .index => {
            // Simple indexing: a[b]
            // Check for negative index
            if (isNegativeConstant(subscript.slice.index.*)) {
                // Need block to access .len
                try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, "; break :blk __s[");
                try genSliceIndex(self, subscript.slice.index.*, true);
                try self.output.appendSlice(self.allocator, "]; }");
            } else {
                // Positive index - simple subscript
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, "[");
                try genExpr(self, subscript.slice.index.*);
                try self.output.appendSlice(self.allocator, "]");
            }
        },
        .slice => |slice_range| {
            // Slicing: a[start:end] or a[start:end:step]
            const has_step = slice_range.step != null;
            const needs_len = slice_range.upper == null;

            if (has_step) {
                // With step: use slice with step calculation
                // Need to check if this is string or list slicing
                const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

                if (value_type == .string) {
                    // String slicing with step (supports negative step for reverse iteration)
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.output.appendSlice(self.allocator, "; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true);
                        try self.output.appendSlice(self.allocator, ")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.output.appendSlice(self.allocator, "; var __result = std.ArrayList(u8){}; if (__step > 0) { var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) { try __result.append(std.heap.page_allocator, __s[__i]); } } else if (__step < 0) { var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) { try __result.append(std.heap.page_allocator, __s[@intCast(__i)]); } } break :blk try __result.toOwnedSlice(std.heap.page_allocator); }");
                } else if (value_type == .list) {
                    // List slicing with step (supports negative step for reverse iteration)
                    // Get element type to generate proper ArrayList
                    const elem_type = value_type.list.*;

                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __step: i64 = ");
                    try genExpr(self, slice_range.step.?.*);
                    try self.output.appendSlice(self.allocator, "; const __start: usize = ");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        // Default start: 0 for positive step, len-1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) 0 else if (__s.len > 0) __s.len - 1 else 0");
                    }

                    try self.output.appendSlice(self.allocator, "; const __end_i64: i64 = ");

                    if (slice_range.upper) |upper| {
                        try self.output.appendSlice(self.allocator, "@intCast(");
                        try genSliceIndex(self, upper.*, true);
                        try self.output.appendSlice(self.allocator, ")");
                    } else {
                        // Default end: len for positive step, -1 for negative step
                        try self.output.appendSlice(self.allocator, "if (__step > 0) @as(i64, @intCast(__s.len)) else -1");
                    }

                    try self.output.appendSlice(self.allocator, "; var __result = std.ArrayList(");

                    // Generate element type
                    try elem_type.toZigType(self.allocator, &self.output);

                    try self.output.appendSlice(self.allocator, "){}; if (__step > 0) { var __i = __start; while (@as(i64, @intCast(__i)) < __end_i64) : (__i += @intCast(__step)) { try __result.append(std.heap.page_allocator, __s[__i]); } } else if (__step < 0) { var __i: i64 = @intCast(__start); while (__i > __end_i64) : (__i += __step) { try __result.append(std.heap.page_allocator, __s[@intCast(__i)]); } } break :blk try __result.toOwnedSlice(std.heap.page_allocator); }");
                } else {
                    // Unknown type - generate error
                    try self.output.appendSlice(self.allocator, "@compileError(\"Slicing with step requires string or list type\")");
                }
            } else if (needs_len) {
                // Need length for upper bound - use block expression with bounds checking
                try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                try genExpr(self, subscript.value.*);
                try self.output.appendSlice(self.allocator, "; const __start = @min(");

                if (slice_range.lower) |lower| {
                    try genSliceIndex(self, lower.*, true);
                } else {
                    try self.output.appendSlice(self.allocator, "0");
                }

                try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start <= __s.len) __s[__start..__s.len] else \"\"; }");
            } else {
                // Simple slice with both bounds known - need to check for negative indices
                const has_negative = blk: {
                    if (slice_range.lower) |lower| {
                        if (isNegativeConstant(lower.*)) break :blk true;
                    }
                    if (slice_range.upper) |upper| {
                        if (isNegativeConstant(upper.*)) break :blk true;
                    }
                    break :blk false;
                };

                if (has_negative) {
                    // Need block expression to handle negative indices with bounds checking
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __start = @min(");

                    if (slice_range.lower) |lower| {
                        try genSliceIndex(self, lower.*, true);
                    } else {
                        try self.output.appendSlice(self.allocator, "0");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); const __end = @min(");

                    if (slice_range.upper) |upper| {
                        try genSliceIndex(self, upper.*, true);
                    } else {
                        try self.output.appendSlice(self.allocator, "__s.len");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start < __end) __s[__start..__end] else \"\"; }");
                } else {
                    // No negative indices - but still need bounds checking for Python semantics
                    // Python allows out-of-bounds slices, Zig doesn't
                    try self.output.appendSlice(self.allocator, "blk: { const __s = ");
                    try genExpr(self, subscript.value.*);
                    try self.output.appendSlice(self.allocator, "; const __start = @min(");

                    if (slice_range.lower) |lower| {
                        try genExpr(self, lower.*);
                    } else {
                        try self.output.appendSlice(self.allocator, "0");
                    }

                    try self.output.appendSlice(self.allocator, ", __s.len); const __end = @min(");
                    try genExpr(self, slice_range.upper.?.*);
                    try self.output.appendSlice(self.allocator, ", __s.len); break :blk if (__start < __end) __s[__start..__end] else \"\"; }");
                }
            }
        },
    }
}

/// Generate attribute access (obj.attr)
fn genAttribute(self: *NativeCodegen, attr: ast.Node.Attribute) CodegenError!void {
    // self.x -> self.x (direct translation in Zig)
    try genExpr(self, attr.value.*);
    try self.output.appendSlice(self.allocator, ".");
    try self.output.appendSlice(self.allocator, attr.attr);
}

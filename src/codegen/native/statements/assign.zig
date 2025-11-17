/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Check if an expression contains a reference to a variable name
/// Used to detect self-referencing assignments like: x = x + 1
fn valueContainsName(node: ast.Node, name: []const u8) bool {
    switch (node) {
        .name => |n| return std.mem.eql(u8, n.id, name),
        .binop => |binop| {
            return valueContainsName(binop.left.*, name) or valueContainsName(binop.right.*, name);
        },
        .unaryop => |unary| {
            return valueContainsName(unary.operand.*, name);
        },
        .call => |call| {
            if (valueContainsName(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (valueContainsName(arg, name)) return true;
            }
            return false;
        },
        .attribute => |attr| {
            return valueContainsName(attr.value.*, name);
        },
        .subscript => |subscript| {
            if (valueContainsName(subscript.value.*, name)) return true;
            switch (subscript.slice) {
                .index => |idx| return valueContainsName(idx.*, name),
                .slice => |slice| {
                    if (slice.lower) |lower| {
                        if (valueContainsName(lower.*, name)) return true;
                    }
                    if (slice.upper) |upper| {
                        if (valueContainsName(upper.*, name)) return true;
                    }
                    if (slice.step) |step| {
                        if (valueContainsName(step.*, name)) return true;
                    }
                    return false;
                },
            }
        },
        .list => |list| {
            for (list.elts) |elt| {
                if (valueContainsName(elt, name)) return true;
            }
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                if (valueContainsName(elt, name)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Handle tuple unpacking: a, b = (1, 2)
    if (assign.targets.len == 1 and assign.targets[0] == .tuple) {
        const target_tuple = assign.targets[0].tuple;

        // Generate: const __unpack_tmp = value_expr;
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const __unpack_tmp = ");
        try self.genExpr(assign.value.*);
        try self.output.appendSlice(self.allocator, ";\n");

        // Generate: const a = __unpack_tmp.@"0";
        //           const b = __unpack_tmp.@"1";
        for (target_tuple.elts, 0..) |target, i| {
            if (target == .name) {
                const var_name = target.name.id;
                const is_first_assignment = !self.isDeclared(var_name);

                try self.emitIndent();
                if (is_first_assignment) {
                    try self.output.appendSlice(self.allocator, "const ");
                    try self.declareVar(var_name);
                }
                try self.output.appendSlice(self.allocator, var_name);
                try self.output.writer(self.allocator).print(" = __unpack_tmp.@\"{d}\";\n", .{i});
            }
        }
        return;
    }

    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;

            // ArrayLists, dicts, and class instances need var instead of const for mutation
            const is_arraylist = (assign.value.* == .list and assign.value.list.elts.len == 0);
            const is_dict = (assign.value.* == .dict);
            const is_class_instance = blk: {
                if (assign.value.* == .call and assign.value.call.func.* == .name) {
                    const name = assign.value.call.func.name.id;
                    // Class names start with uppercase
                    break :blk name.len > 0 and std.ascii.isUpper(name[0]);
                }
                break :blk false;
            };

            // Check if value allocates memory
            const is_allocated_string = blk: {
                if (assign.value.* == .call) {
                    // String method calls that allocate new strings
                    if (assign.value.call.func.* == .attribute) {
                        const attr = assign.value.call.func.attribute;
                        const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch break :blk false;

                        if (obj_type == .string) {
                            const method_name = attr.attr;
                            // All string methods that allocate and return new strings
                            const allocating_methods = [_][]const u8{
                                "upper", "lower", "strip", "lstrip", "rstrip",
                                "replace", "capitalize", "title", "swapcase",
                                "center", "ljust", "rjust", "join",
                            };

                            for (allocating_methods) |method| {
                                if (std.mem.eql(u8, method_name, method)) {
                                    break :blk true;
                                }
                            }
                        }
                    }
                    // Built-in functions that allocate: sorted(), reversed()
                    if (assign.value.call.func.* == .name) {
                        const func_name = assign.value.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "sorted") or
                            std.mem.eql(u8, func_name, "reversed"))
                        {
                            break :blk true;
                        }
                    }
                }
                // String concatenation allocates: s1 + s2
                if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                    const left_type = try self.type_inferrer.inferExpr(assign.value.binop.left.*);
                    const right_type = try self.type_inferrer.inferExpr(assign.value.binop.right.*);
                    if (left_type == .string or right_type == .string) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            // Check if this is first assignment or reassignment
            const is_first_assignment = !self.isDeclared(var_name);

            try self.emitIndent();
            if (is_first_assignment) {
                // First assignment: decide between const and var
                // Use var only for:
                // - Mutable collections (ArrayLists, dicts, class instances)
                // - Variables that are actually reassigned later (check mutability analysis)
                // Use const for everything else (literals, function results, etc.)
                const is_mutated = self.semantic_info.isMutated(var_name);

                // Fallback: check if value contains a self-reference (x = x + 1 pattern)
                const has_self_ref = valueContainsName(assign.value.*, var_name);

                const needs_var = is_arraylist or is_dict or is_class_instance or is_mutated or has_self_ref;

                if (needs_var) {
                    try self.output.appendSlice(self.allocator, "var ");
                } else {
                    try self.output.appendSlice(self.allocator, "const ");
                }
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types that aren't dicts, lists, tuples, or ArrayLists
                // For lists/ArrayLists/dicts/tuples, let Zig infer the type from the initializer
                // For unknown types (json.loads, etc.), let Zig infer
                const is_list = (value_type == .list);
                const is_tuple = (value_type == .tuple);
                if (value_type != .unknown and !is_dict and !is_arraylist and !is_list and !is_tuple) {
                    try self.output.appendSlice(self.allocator, ": ");
                    try value_type.toZigType(self.allocator, &self.output);
                }

                try self.output.appendSlice(self.allocator, " = ");

                // Mark as declared
                try self.declareVar(var_name);
            } else {
                // Reassignment: x = value (no var/const keyword!)
                try self.output.appendSlice(self.allocator, var_name);
                try self.output.appendSlice(self.allocator, " = ");
                // No type annotation on reassignment
            }

            // Special handling for string concatenation with nested operations
            // s1 + " " + s2 needs intermediate temps
            if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(assign.value.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(assign.value.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    // Collect all parts of the concatenation
                    var parts = std.ArrayList(ast.Node){};
                    defer parts.deinit(self.allocator);

                    try flattenConcat(self, assign.value.*, &parts);

                    // Generate concat with all parts at once
                    try self.output.appendSlice(self.allocator, "try std.mem.concat(allocator, u8, &[_][]const u8{ ");
                    for (parts.items, 0..) |part, i| {
                        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                        try self.genExpr(part);
                    }
                    try self.output.appendSlice(self.allocator, " });\n");

                    // Add defer cleanup
                    if (is_first_assignment) {
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("defer allocator.free({s});\n", .{var_name});
                    }
                    return;
                }
            }

            // Emit value
            try self.genExpr(assign.value.*);

            try self.output.appendSlice(self.allocator, ";\n");

            // Add defer cleanup for ArrayLists and Dicts (only on first assignment)
            if (is_first_assignment and is_arraylist) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s}.deinit(allocator);\n", .{var_name});
            }
            if (is_first_assignment and is_dict) {
                // Check if dict has mixed types (which means string values with allocations)
                const has_mixed_types = blk: {
                    if (assign.value.dict.values.len == 0) break :blk false;
                    const first_type = try self.type_inferrer.inferExpr(assign.value.dict.values[0]);
                    for (assign.value.dict.values[1..]) |value| {
                        const this_type = try self.type_inferrer.inferExpr(value);
                        if (@as(std.meta.Tag(@TypeOf(first_type)), first_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                // If mixed types, need to free string values before deinit
                if (has_mixed_types) {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("defer {{\n", .{});
                    self.indent();
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("var iter = {s}.valueIterator();\n", .{var_name});
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "while (iter.next()) |value| {\n");
                    self.indent();
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "allocator.free(value.*);\n");
                    self.dedent();
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "}\n");
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("{s}.deinit();\n", .{var_name});
                    self.dedent();
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "}\n");
                } else {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("defer {s}.deinit();\n", .{var_name});
                }
            }
            // Add defer cleanup for allocated strings (upper/lower/replace/sorted/reversed - only on first assignment)
            if (is_first_assignment and is_allocated_string) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer allocator.free({s});\n", .{var_name});
            }
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value)
            try self.emitIndent();
            try self.genExpr(target);
            try self.output.appendSlice(self.allocator, " = ");
            try self.genExpr(assign.value.*);
            try self.output.appendSlice(self.allocator, ";\n");
        }
    }
}

/// Flatten nested string concatenation into a list of parts
/// (s1 + " ") + s2 becomes [s1, " ", s2]
fn flattenConcat(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        // Check if this is string concat
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);

        if (left_type == .string or right_type == .string) {
            // Recursively flatten left side
            try flattenConcat(self, node.binop.left.*, parts);
            // Recursively flatten right side
            try flattenConcat(self, node.binop.right.*, parts);
            return;
        }
    }

    // Not a string concat, just add the node
    try parts.append(self.allocator, node);
}

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

    // Emit target (variable name)
    try self.genExpr(aug.target.*);
    try self.output.appendSlice(self.allocator, " = ");

    // Special handling for floor division and power
    if (aug.op == .FloorDiv) {
        try self.output.appendSlice(self.allocator, "@divFloor(");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    if (aug.op == .Pow) {
        try self.output.appendSlice(self.allocator, "std.math.pow(i64, ");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    if (aug.op == .Mod) {
        try self.output.appendSlice(self.allocator, "@rem(");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    // Regular operators: +=, -=, *=, /=
    try self.genExpr(aug.target.*);

    const op_str = switch (aug.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        else => " ? ",
    };
    try self.output.appendSlice(self.allocator, op_str);

    try self.genExpr(aug.value.*);
    try self.output.appendSlice(self.allocator, ";\n");
}

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const genPrint = @import("misc.zig").genPrint;
            try genPrint(self, expr.call.args);
            return;
        }
    }

    // Discard string constants (docstrings) by assigning to _
    // Zig requires all non-void values to be used
    if (expr == .constant and expr.constant.value == .string) {
        try self.output.appendSlice(self.allocator, "_ = ");
    }

    try self.genExpr(expr);
    try self.output.appendSlice(self.allocator, ";\n");
}

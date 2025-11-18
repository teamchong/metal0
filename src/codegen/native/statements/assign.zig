/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");

/// Check if a list contains only literal values
fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false;

    for (list.elts) |elem| {
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements have the same type
fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Handle tuple unpacking: a, b = (1, 2)
    if (assign.targets.len == 1 and assign.targets[0] == .tuple) {
        const target_tuple = assign.targets[0].tuple;

        // Generate unique temporary variable name
        const tmp_name = try std.fmt.allocPrint(self.allocator, "__unpack_tmp_{d}", .{self.unpack_counter});
        defer self.allocator.free(tmp_name);
        self.unpack_counter += 1;

        // Generate: const __unpack_tmp_N = value_expr;
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const ");
        try self.output.appendSlice(self.allocator, tmp_name);
        try self.output.appendSlice(self.allocator, " = ");
        try self.genExpr(assign.value.*);
        try self.output.appendSlice(self.allocator, ";\n");

        // Generate: const a = __unpack_tmp_N.@"0";
        //           const b = __unpack_tmp_N.@"1";
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
                try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
            }
        }
        return;
    }

    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;

            // Check collection types (still used for type annotation logic)
            // Constant homogeneous lists become arrays, not ArrayLists
            const is_constant_array = blk: {
                if (assign.value.* != .list) break :blk false;
                const list = assign.value.list;
                // If it's a constant list, it becomes an array
                if (isConstantList(list) and allSameType(list.elts)) break :blk true;
                break :blk false;
            };
            const is_arraylist = blk: {
                if (assign.value.* != .list) break :blk false;
                const list = assign.value.list;
                // If it's a constant list, it becomes an array, not ArrayList
                if (isConstantList(list) and allSameType(list.elts)) break :blk false;
                break :blk true;
            };
            const is_listcomp = (assign.value.* == .listcomp);
            const is_dict = (assign.value.* == .dict);
            const is_class_instance = blk: {
                if (assign.value.* == .call and assign.value.call.func.* == .name) {
                    const name = assign.value.call.func.name.id;
                    // Class names start with uppercase (PascalCase convention)
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
                            // NOTE: strip/lstrip/rstrip use std.mem.trim - they DON'T allocate!
                            const allocating_methods = [_][]const u8{
                                "upper", "lower",
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

            // Try compile-time evaluation FIRST
            if (self.comptime_evaluator.tryEval(assign.value.*)) |comptime_val| {
                // Only apply for simple types (no strings/lists that allocate during evaluation)
                // TODO: Strings and lists need proper arena allocation to avoid memory leaks
                const is_simple_type = switch (comptime_val) {
                    .int, .float, .bool => true,
                    .string, .list => false,
                };

                if (is_simple_type) {
                    // Check mutability BEFORE emitting
                    const is_mutable = if (is_first_assignment)
                        self.semantic_info.isMutated(var_name)
                    else
                        false;  // Reassignments don't declare

                    // Successfully evaluated at compile time!
                    try emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);
                    if (is_first_assignment) {
                        try self.declareVar(var_name);
                    }
                    return;
                }
                // Fall through to runtime codegen for strings/lists
                // Don't free - these are either AST-owned or will leak (TODO: arena)
            }

            try self.emitIndent();
            if (is_first_assignment) {
                // First assignment: decide between const and var
                // Use var if variable is mutated OR if it's a mutable collection/class instance
                const is_mutated = self.semantic_info.isMutated(var_name);

                // ArrayLists, dicts, and class instances need var (for mutation and deinit)
                const needs_var = is_mutated or is_arraylist or is_dict or is_class_instance;

                if (needs_var) {
                    try self.output.appendSlice(self.allocator, "var ");
                } else {
                    try self.output.appendSlice(self.allocator, "const ");
                }
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types that aren't dicts, lists, tuples, closures, or ArrayLists
                // For lists/ArrayLists/dicts/tuples/closures, let Zig infer the type from the initializer
                // For unknown types (json.loads, etc.), let Zig infer
                const is_list = (value_type == .list);
                const is_tuple = (value_type == .tuple);
                const is_closure = (value_type == .closure);
                if (value_type != .unknown and !is_dict and !is_arraylist and !is_list and !is_tuple and !is_closure) {
                    try self.output.appendSlice(self.allocator, ": ");
                    try value_type.toZigType(self.allocator, &self.output);
                }

                try self.output.appendSlice(self.allocator, " = ");

                // Mark as declared
                try self.declareVar(var_name);

                // Track if this variable holds a constant array
                if (is_constant_array) {
                    const var_name_copy = try self.allocator.dupe(u8, var_name);
                    try self.array_vars.put(var_name_copy, {});
                }
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

                    try helpers.flattenConcat(self, assign.value.*, &parts);

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

            const lambda_closure = @import("../expressions/lambda_closure.zig");
            const lambda_mod = @import("../expressions/lambda.zig");

            // Track closure factories: make_adder = lambda x: lambda y: x + y
            if (assign.value.* == .lambda and assign.value.lambda.body.* == .lambda) {
                try lambda_closure.markAsClosureFactory(self, var_name);
            }

            // Track simple closures: x = 10; f = lambda y: y + x (captures outer variable)
            if (assign.value.* == .lambda) {
                // Check if this lambda captures outer variables
                if (lambda_mod.lambdaCapturesVars(self, assign.value.lambda)) {
                    // This lambda generated a closure struct, mark it
                    try lambda_closure.markAsClosure(self, var_name);
                } else {
                    // Simple lambda (no captures) - track as function pointer
                    const key = try self.allocator.dupe(u8, var_name);
                    try self.lambda_vars.put(key, {});

                    // Register lambda return type for type inference
                    const return_type = try lambda_mod.getLambdaReturnType(self, assign.value.lambda);
                    try self.type_inferrer.func_return_types.put(var_name, return_type);
                }
            }

            // Track closure instances: add_five = make_adder(5)
            if (assign.value.* == .call and assign.value.call.func.* == .name) {
                const called_func = assign.value.call.func.name.id;
                if (self.closure_factories.contains(called_func)) {
                    // This is calling a closure factory, so the result is a closure
                    try lambda_closure.markAsClosure(self, var_name);
                }
            }

            // Add defer cleanup for ArrayLists and Dicts (only on first assignment)
            if (is_first_assignment and is_arraylist) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s}.deinit(allocator);\n", .{var_name});
            }
            // Add defer cleanup for list comprehensions (return slices, not ArrayLists)
            if (is_first_assignment and is_listcomp) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer allocator.free({s});\n", .{var_name});
            }
            if (is_first_assignment and is_dict) {
                // Check if dict will use comptime path (all constants AND compatible types)
                // Must match the logic in collections.zig to avoid mismatch!
                var is_comptime_dict = true;
                for (assign.value.dict.keys) |key| {
                    if (!helpers.isComptimeConstant(key)) {
                        is_comptime_dict = false;
                        break;
                    }
                }
                if (is_comptime_dict) {
                    for (assign.value.dict.values) |value| {
                        if (!helpers.isComptimeConstant(value)) {
                            is_comptime_dict = false;
                            break;
                        }
                    }
                }

                // Even if all constants, check type compatibility (matches collections.zig logic)
                if (is_comptime_dict and assign.value.dict.values.len > 0) {
                    const first_type = try self.type_inferrer.inferExpr(assign.value.dict.values[0]);
                    for (assign.value.dict.values[1..]) |value| {
                        const this_type = try self.type_inferrer.inferExpr(value);
                        const tags_match = @as(std.meta.Tag(@TypeOf(first_type)), first_type) ==
                                          @as(std.meta.Tag(@TypeOf(this_type)), this_type);
                        const is_int_float_mix = (first_type == .int and this_type == .float) or
                                                 (first_type == .float and this_type == .int);
                        if (!tags_match and !is_int_float_mix) {
                            // Mixed types → will use runtime path → NOT comptime!
                            is_comptime_dict = false;
                            break;
                        }
                    }
                }

                // Check if dict needs complex cleanup (string values that were allocated)
                // Comptime dicts use string literals (no allocation) → simple cleanup
                // Runtime dicts with mixed types convert to strings → need value freeing
                const needs_value_cleanup = blk: {
                    if (is_comptime_dict) break :blk false;  // Comptime dicts never need value cleanup
                    if (assign.value.dict.values.len == 0) break :blk false;

                    // Check if values have different types (will be widened to string)
                    const first_type = try self.type_inferrer.inferExpr(assign.value.dict.values[0]);
                    for (assign.value.dict.values[1..]) |value| {
                        const this_type = try self.type_inferrer.inferExpr(value);
                        // Direct enum tag comparison
                        const first_tag = @as(std.meta.Tag(@TypeOf(first_type)), first_type);
                        const this_tag = @as(std.meta.Tag(@TypeOf(this_type)), this_type);
                        if (first_tag != this_tag) {
                            // Different types → runtime path will allocate strings
                            break :blk true;
                        }
                    }

                    // All same type → no value cleanup needed
                    break :blk false;
                };

                // If needs value cleanup, free all string values before deinit
                if (needs_value_cleanup) {
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

    const before_len = self.output.items.len;
    try self.genExpr(expr);

    // Check if generated code ends with '}' (block statement)
    // Blocks in statement position don't need semicolons
    const generated = self.output.items[before_len..];
    const ends_with_block = generated.len > 0 and generated[generated.len - 1] == '}';

    if (ends_with_block) {
        try self.output.appendSlice(self.allocator, "\n");
    } else {
        try self.output.appendSlice(self.allocator, ";\n");
    }
}

/// Emit assignment for compile-time constant value
fn emitComptimeAssignment(
    self: *NativeCodegen,
    var_name: []const u8,
    value: @import("../../../analysis/comptime_eval.zig").ComptimeValue,
    is_first_assignment: bool,
    is_mutable: bool,
) CodegenError!void {
    try self.emitIndent();

    if (is_first_assignment) {
        // Use var for mutable variables, const for immutable
        if (is_mutable) {
            try self.output.appendSlice(self.allocator, "var ");
        } else {
            try self.output.appendSlice(self.allocator, "const ");
        }
    }

    try self.output.appendSlice(self.allocator, var_name);

    if (is_first_assignment) {
        // Emit type annotation
        try self.output.appendSlice(self.allocator, ": ");
        switch (value) {
            .int => try self.output.appendSlice(self.allocator, "i64"),
            .float => try self.output.appendSlice(self.allocator, "f64"),
            .bool => try self.output.appendSlice(self.allocator, "bool"),
            .string => try self.output.appendSlice(self.allocator, "[]const u8"),
            .list => |items| {
                if (items.len == 0) {
                    try self.output.appendSlice(self.allocator, "[0]i64"); // Empty list default type
                } else {
                    // Infer element type from first element
                    const elem_type = switch (items[0]) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string => "[]const u8",
                        .list => "ComptimeValue", // Nested lists not fully supported
                    };
                    try self.output.writer(self.allocator).print("[{d}]{s}", .{ items.len, elem_type });
                }
            },
        }
    }

    try self.output.appendSlice(self.allocator, " = ");

    // Emit value
    switch (value) {
        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
        .float => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
        .bool => |v| {
            const bool_str = if (v) "true" else "false";
            try self.output.appendSlice(self.allocator, bool_str);
        },
        .string => |v| {
            // Escape the string properly
            try self.output.appendSlice(self.allocator, "\"");
            for (v) |c| {
                switch (c) {
                    '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                    '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                    '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                    '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                    '"' => try self.output.appendSlice(self.allocator, "\\\""),
                    else => try self.output.append(self.allocator, c),
                }
            }
            try self.output.appendSlice(self.allocator, "\"");
        },
        .list => |items| {
            if (items.len == 0) {
                try self.output.appendSlice(self.allocator, ".{}");
            } else {
                try self.output.appendSlice(self.allocator, ".{ ");
                for (items, 0..) |item, i| {
                    if (i > 0) try self.output.appendSlice(self.allocator, ", ");

                    switch (item) {
                        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
                        .float => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
                        .bool => |v| {
                            const bool_str = if (v) "true" else "false";
                            try self.output.appendSlice(self.allocator, bool_str);
                        },
                        .string => |v| try self.output.writer(self.allocator).print("\"{s}\"", .{v}),
                        .list => {
                            // Nested lists not fully supported yet
                            try self.output.appendSlice(self.allocator, ".{}");
                        },
                    }
                }
                try self.output.appendSlice(self.allocator, " }");
            }
        },
    }

    try self.output.appendSlice(self.allocator, ";\n");
}

/// Free memory allocated for comptime value
fn freeComptimeValue(allocator: std.mem.Allocator, value: @import("../../../analysis/comptime_eval.zig").ComptimeValue) void {
    switch (value) {
        .string => |s| allocator.free(s),
        .list => |items| {
            for (items) |item| {
                freeComptimeValue(allocator, item);
            }
            allocator.free(items);
        },
        else => {}, // int, float, bool don't allocate
    }
}

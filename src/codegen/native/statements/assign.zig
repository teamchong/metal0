/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");

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
            const is_dictcomp = (assign.value.* == .dictcomp);
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
                    try comptimeHelpers.emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);
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
                // Dictcomps return immutable HashMaps, so they don't need var
                const needs_var = is_mutated or is_arraylist or is_dict or is_class_instance;

                if (needs_var) {
                    try self.output.appendSlice(self.allocator, "var ");
                } else {
                    try self.output.appendSlice(self.allocator, "const ");
                }
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types that aren't dicts, dictcomps, lists, tuples, closures, or ArrayLists
                // For lists/ArrayLists/dicts/dictcomps/tuples/closures, let Zig infer the type from the initializer
                // For unknown types (json.loads, etc.), let Zig infer
                const is_list = (value_type == .list);
                const is_tuple = (value_type == .tuple);
                const is_closure = (value_type == .closure);
                const is_dict_type = (value_type == .dict);
                if (value_type != .unknown and !is_dict and !is_dictcomp and !is_dict_type and !is_arraylist and !is_list and !is_tuple and !is_closure) {
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

                // Track if this variable holds an array slice (subscript of constant array)
                const is_array_slice = blk: {
                    if (assign.value.* == .subscript and assign.value.subscript.slice == .slice) {
                        if (assign.value.subscript.value.* == .name) {
                            break :blk self.isArrayVar(assign.value.subscript.value.name.id);
                        }
                    }
                    break :blk false;
                };
                if (is_array_slice) {
                    const var_name_copy = try self.allocator.dupe(u8, var_name);
                    try self.array_slice_vars.put(var_name_copy, {});
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
                    try deferCleanup.emitStringConcatDefer(self, var_name, is_first_assignment);
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

            // Add defer cleanup based on assignment type
            try deferCleanup.emitDeferCleanups(
                self,
                var_name,
                is_first_assignment,
                is_arraylist,
                is_listcomp,
                is_dict,
                is_allocated_string,
                assign.value.*,
            );
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

// Comptime assignment functions moved to assign_comptime.zig

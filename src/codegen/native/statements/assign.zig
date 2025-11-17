/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

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
                    // Method calls that allocate: upper(), lower(), replace()
                    if (assign.value.call.func.* == .attribute) {
                        const method_name = assign.value.call.func.attribute.attr;
                        if (std.mem.eql(u8, method_name, "upper") or
                            std.mem.eql(u8, method_name, "lower") or
                            std.mem.eql(u8, method_name, "replace"))
                        {
                            break :blk true;
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
                // Use var for:
                // - Mutable collections (ArrayLists, dicts)
                // - Simple literals that are likely accumulators (0, 1, true, false)
                // Use const for:
                // - Function call results
                // - Complex expressions
                // - Strings and arrays
                const is_simple_literal = switch (assign.value.*) {
                    .constant => true,
                    .binop => false, // Expressions like (a + b)
                    .call => false,   // Function calls
                    else => false,
                };
                const needs_var = is_arraylist or is_dict or is_class_instance or
                                 (is_simple_literal and (value_type == .int or value_type == .float or value_type == .bool));

                if (needs_var) {
                    try self.output.appendSlice(self.allocator, "var ");
                } else {
                    try self.output.appendSlice(self.allocator, "const ");
                }
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types that aren't dicts, lists, or ArrayLists
                // For lists/ArrayLists/dicts, let Zig infer the type from the initializer
                // For unknown types (json.loads, etc.), let Zig infer
                const is_list = (value_type == .list);
                if (value_type != .unknown and !is_dict and !is_arraylist and !is_list) {
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
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s}.deinit();\n", .{var_name});
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

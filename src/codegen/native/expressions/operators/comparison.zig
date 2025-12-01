/// Comparison operations: ==, !=, <, <=, >, >=, in, not in, is, is not
/// Handles chained comparisons, string comparisons, container membership, identity checks
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;

/// Check if an expression is a call to eval()
fn isEvalCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;
    if (call.func.* != .name) return false;
    return std.mem.eql(u8, call.func.name.id, "eval");
}

/// Check if an expression produces a Zig block expression that needs parentheses
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true,
        .list => true,
        .dict => true,
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true,
        .attribute => true,
        .compare => true,
        else => false,
    };
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.inferExprScoped(compare.left.*);

    // NumPy array comparisons return boolean arrays (element-wise)
    // Only supports single comparison (no chained comparisons for arrays)
    if (left_type == .numpy_array and compare.ops.len == 1) {
        const op = compare.ops[0];
        const op_str = switch (op) {
            .Lt => ".lt",
            .LtEq => ".le",
            .Gt => ".gt",
            .GtEq => ".ge",
            .Eq => ".eq",
            .NotEq => ".ne",
            else => null,
        };

        if (op_str) |op_enum| {
            // Check if right side is a constant (scalar comparison)
            const right = compare.comparators[0];
            const right_type = try self.inferExprScoped(right);

            if (right_type == .int or right_type == .float or
                (right == .constant and (right.constant.value == .int or right.constant.value == .float)))
            {
                // arr > scalar → numpy.compareScalar(arr, scalar, .gt, allocator)
                try self.emit("try numpy.compareScalar(");
                try genExpr(self, compare.left.*);
                try self.emit(", @as(f64, ");
                try genExpr(self, right);
                try self.emit("), ");
                try self.emit(op_enum);
                try self.emit(", allocator)");
            } else {
                // arr1 > arr2 → numpy.compareArrays(arr1, arr2, .gt, allocator)
                try self.emit("try numpy.compareArrays(");
                try genExpr(self, compare.left.*);
                try self.emit(", ");
                try genExpr(self, right);
                try self.emit(", ");
                try self.emit(op_enum);
                try self.emit(", allocator)");
            }
            return;
        }
    }

    // For chained comparisons (more than 1 op), wrap everything in parens
    const is_chained = compare.ops.len > 1;
    if (is_chained) {
        try self.emit("(");
    }

    for (compare.ops, 0..) |op, i| {
        // Add "and" between comparisons for chained comparisons
        if (i > 0) {
            try self.emit(" and ");
        }

        // For chained comparisons, wrap each individual comparison in parens
        if (is_chained) {
            try self.emit("(");
        }

        const right_type = try self.inferExprScoped(compare.comparators[i]);

        // For chained comparisons after the first, left side is the previous comparator
        const current_left = if (i == 0) compare.left.* else compare.comparators[i - 1];
        const current_left_type = if (i == 0) left_type else try self.inferExprScoped(compare.comparators[i - 1]);

        // Special handling for string comparisons
        // Also handle cases where one side is .unknown (e.g., json.loads) comparing to string
        const left_is_string = (current_left_type == .string);
        const right_is_string = (right_type == .string);
        const either_string = left_is_string or right_is_string;
        const neither_unknown = (current_left_type != .unknown and right_type != .unknown);

        if ((left_is_string and right_is_string) or (either_string and !neither_unknown)) {
            switch (op) {
                .Eq => {
                    try self.emit("std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .NotEq => {
                    try self.emit("!std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .In => {
                    // String substring check: std.mem.indexOf(u8, haystack, needle) != null
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") != null)");
                },
                .NotIn => {
                    // String substring check (negated)
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") == null)");
                },
                .Is => {
                    // Identity comparison for strings: compare pointer/length
                    try self.emit("(");
                    try genExpr(self, current_left);
                    try self.emit(".ptr == ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".ptr and ");
                    try genExpr(self, current_left);
                    try self.emit(".len == ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".len)");
                },
                .IsNot => {
                    // Negated identity comparison for strings
                    try self.emit("(");
                    try genExpr(self, current_left);
                    try self.emit(".ptr != ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".ptr or ");
                    try genExpr(self, current_left);
                    try self.emit(".len != ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".len)");
                },
                else => {
                    // String comparison operators other than == and != not supported
                    try genExpr(self, current_left);
                    const op_str = switch (op) {
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " == ", // Fallback to == for any unknown ops
                    };
                    try self.emit(op_str);
                    try genExpr(self, compare.comparators[i]);
                },
            }
        }
        // Handle 'in' operator for lists
        else if (op == .In or op == .NotIn) {
            if (right_type == .list) {
                // List membership check: std.mem.indexOfScalar(T, slice, value) != null
                const elem_type = right_type.list.*;
                const type_str = elem_type.toSimpleZigType();

                try self.emit("(std.mem.indexOfScalar(");
                try self.emit(type_str);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]); // list/slice
                try self.emit(", ");
                try genExpr(self, current_left); // item to search for

                if (op == .In) {
                    try self.emit(") != null)");
                } else {
                    try self.emit(") == null)");
                }
            } else if (right_type == .dict) {
                // Dict key check: dict.contains(key)
                // For dict literals, wrap in block to assign to temp var
                const is_literal = compare.comparators[i] == .dict;
                if (is_literal) {
                    try self.emit("(blk: { const __d = ");
                    try genExpr(self, compare.comparators[i]); // dict literal
                    if (op == .In) {
                        try self.emit("; break :blk __d.contains(");
                    } else {
                        try self.emit("; break :blk !__d.contains(");
                    }
                    try genExpr(self, current_left); // key
                    try self.emit("); })");
                } else {
                    if (op == .In) {
                        try genExpr(self, compare.comparators[i]); // dict var
                        try self.emit(".contains(");
                        try genExpr(self, current_left); // key
                        try self.emit(")");
                    } else {
                        try self.emit("!");
                        try genExpr(self, compare.comparators[i]); // dict var
                        try self.emit(".contains(");
                        try genExpr(self, current_left); // key
                        try self.emit(")");
                    }
                }
            } else {
                // Fallback for arrays and unrecognized types
                // Infer element type from the item being searched for

                // String arrays/tuples need special handling - can't use indexOfScalar
                // because strings require std.mem.eql for comparison, not ==
                // Also check if comparator is a tuple of strings
                const is_string_search = current_left_type == .string or
                    (compare.comparators[i] == .tuple and compare.comparators[i].tuple.elts.len > 0 and
                    compare.comparators[i].tuple.elts[0] == .constant and
                    compare.comparators[i].tuple.elts[0].constant.value == .string);

                if (is_string_search) {
                    // For 'not in', wrap in negation by emitting ! first
                    if (op == .NotIn) {
                        try self.emit("!");
                    }

                    // Check if container is a tuple - need inline comparisons (can't iterate tuples at runtime)
                    if (compare.comparators[i] == .tuple) {
                        const tuple_elts = compare.comparators[i].tuple.elts;
                        try self.emit("(");
                        for (tuple_elts, 0..) |elt, j| {
                            if (j > 0) try self.emit(" or ");
                            try self.emit("std.mem.eql(u8, ");
                            try genExpr(self, current_left);
                            try self.emit(", ");
                            try genExpr(self, elt);
                            try self.emit(")");
                        }
                        try self.emit(")");
                    } else {
                        // Generate inline block expression that loops through array
                        // Use unique label to avoid collisions with nested expressions
                        const in_label_id = self.block_label_counter;
                        self.block_label_counter += 1;
                        try self.output.writer(self.allocator).print("(in_{d}: {{\n", .{in_label_id});
                        try self.emit("for (");
                        try genExpr(self, compare.comparators[i]); // array
                        try self.emit(") |__item| {\n");
                        try self.emit("if (std.mem.eql(u8, __item, ");
                        try genExpr(self, current_left); // search string
                        try self.output.writer(self.allocator).print(")) break :in_{d} true;\n", .{in_label_id});
                        try self.emit("}\n");
                        try self.output.writer(self.allocator).print("break :in_{d} false;\n", .{in_label_id});
                        try self.emit("})");
                    }
                } else {
                    // Integer and float arrays use indexOfScalar
                    // Use std.meta.Elem to get element type - works for both arrays and slices
                    // Use unique label to avoid collisions with nested expressions
                    const in_label_id = self.block_label_counter;
                    self.block_label_counter += 1;

                    try self.output.writer(self.allocator).print("in_{d}: {{ const __arr = ", .{in_label_id});
                    try genExpr(self, compare.comparators[i]); // array/container
                    try self.emit("; const __val = ");
                    try genExpr(self, current_left); // item to search for
                    // Use std.meta.Elem which works for arrays, slices, and pointers
                    try self.output.writer(self.allocator).print("; const T = std.meta.Elem(@TypeOf(__arr)); break :in_{d} (std.mem.indexOfScalar(T, __arr, __val)", .{in_label_id});
                    if (op == .In) {
                        try self.emit(" != null); }");
                    } else {
                        try self.emit(" == null); }");
                    }
                }
            }
        }
        // Special handling for None comparisons
        else if (current_left_type == .none or right_type == .none) {
            // Check if this is comparing an optional parameter (e.g., base: ?i64) to None
            // If left side is a name that was renamed (optional param), compare to null instead
            // This handles: "if base is None:" -> "if (base == null)"
            const is_optional_param_check = blk: {
                if (right_type == .none and current_left == .name) {
                    const var_name = current_left.name.id;
                    // Check if this variable was renamed from a parameter with None default
                    if (self.var_renames.get(var_name) != null) {
                        break :blk true;
                    }
                    // Also check if it's a method parameter with optional type
                    // (function_signatures tracks methods with defaults)
                    if (self.current_class_name) |class_name| {
                        if (self.current_function_name) |func_name| {
                            var key_buf: [512]u8 = undefined;
                            const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, func_name }) catch "";
                            if (self.function_signatures.get(key)) |_| {
                                // This method has optional params - assume the variable could be optional
                                break :blk true;
                            }
                        }
                    }
                }
                break :blk false;
            };

            if (is_optional_param_check) {
                // Generate: var == null (or != null for "is not None")
                try genExpr(self, current_left);
                if (op == .Is or op == .Eq) {
                    try self.emit(" == null");
                } else {
                    try self.emit(" != null");
                }
            }
            // None comparisons with mixed types: result is known at compile time
            // but we must reference the non-None variable to avoid "unused" errors
            else {
                const cleft_tag = @as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type);
                const right_tag = @as(std.meta.Tag(@TypeOf(right_type)), right_type);
                if (cleft_tag != right_tag) {
                    // One is None, other is not - emit block that references the non-None side
                    // The None side (?void) is allowed to be unused
                    const result = switch (op) {
                        .Eq => "false",
                        .NotEq => "true",
                        else => "false",
                    };
                    // Just emit the known result - variables may be used elsewhere so no need to reference them
                    try self.emit(result);
                } else {
                    // Both are None - compare normally
                    try genExpr(self, current_left);
                    const op_str = switch (op) {
                        .Eq => " == ",
                        .NotEq => " != ",
                        else => " == ", // Other comparisons default to ==
                    };
                    try self.emit(op_str);
                    try genExpr(self, compare.comparators[i]);
                }
            }
        }
        // Handle comparisons involving eval() - returns *PyObject which needs special comparison
        else if (isEvalCall(current_left) or isEvalCall(compare.comparators[i])) {
            // eval() returns *PyObject, need to use runtime comparison functions
            const left_is_eval = isEvalCall(current_left);
            const right_is_eval = isEvalCall(compare.comparators[i]);

            // For == and != with eval() result and integer, use pyObjEqInt
            if (op == .Eq or op == .NotEq) {
                if (op == .NotEq) {
                    try self.emit("!");
                }
                if (left_is_eval and !right_is_eval) {
                    // eval(...) == value
                    try self.emit("runtime.pyObjEqInt(");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                } else if (right_is_eval and !left_is_eval) {
                    // value == eval(...)
                    try self.emit("runtime.pyObjEqInt(");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(", ");
                    try genExpr(self, current_left);
                    try self.emit(")");
                } else {
                    // Both are eval() calls - compare as PyObject pointers
                    try genExpr(self, current_left);
                    try self.emit(" == ");
                    try genExpr(self, compare.comparators[i]);
                }
            } else {
                // For <, >, <=, >= with eval(), extract int value then compare
                // This is a simplification - full Python would handle more types
                try self.emit("(runtime.pyObjToInt(");
                try genExpr(self, current_left);
                try self.emit(")");
                const op_str = switch (op) {
                    .Lt => " < ",
                    .LtEq => " <= ",
                    .Gt => " > ",
                    .GtEq => " >= ",
                    else => " == ",
                };
                try self.emit(op_str);
                if (right_is_eval) {
                    try self.emit("runtime.pyObjToInt(");
                }
                try genExpr(self, compare.comparators[i]);
                if (right_is_eval) {
                    try self.emit(")");
                }
                try self.emit(")");
            }
        }
        // Handle 'is' and 'is not' identity operators
        else if (op == .Is or op == .IsNot) {
            // For primitives (int, bool, None), identity is same as equality
            // For objects/slices, compare pointer addresses
            try genExpr(self, current_left);
            if (op == .Is) {
                try self.emit(" == ");
            } else {
                try self.emit(" != ");
            }
            try genExpr(self, compare.comparators[i]);
        }
        // Handle tuple comparisons (anonymous structs don't support ==)
        else if ((current_left_type == .tuple or current_left == .tuple) and
            (right_type == .tuple or compare.comparators[i] == .tuple))
        {
            // Use std.meta.eql for deep comparison of tuples
            if (op == .NotEq) {
                try self.emit("!");
            }
            try self.emit("std.meta.eql(");
            try genExpr(self, current_left);
            try self.emit(", ");
            try genExpr(self, compare.comparators[i]);
            try self.emit(")");
        }
        // Handle set comparisons (HashMaps don't support ==)
        else if ((current_left_type == .set or current_left == .set) and
            (right_type == .set or compare.comparators[i] == .set))
        {
            // For sets, compare count and all keys match
            // This is a simplified comparison - full Python would check symmetric difference
            const set_label = self.block_label_counter;
            self.block_label_counter += 1;

            if (op == .NotEq) {
                try self.emit("!");
            }
            try self.output.writer(self.allocator).print("set_cmp_{d}: {{ const __s1 = (", .{set_label});
            try genExpr(self, current_left);
            try self.emit("); const __s2 = (");
            try genExpr(self, compare.comparators[i]);
            try self.emit("); if (__s1.count() != __s2.count()) break :set_cmp_");
            try self.output.writer(self.allocator).print("{d} false; ", .{set_label});
            try self.emit("var __all_match = true; var __it = __s1.keyIterator(); ");
            try self.emit("while (__it.next()) |k| { if (!__s2.contains(k.*)) { __all_match = false; break; } } ");
            try self.output.writer(self.allocator).print("break :set_cmp_{d} __all_match; }}", .{set_label});
        }
        // Handle dict comparisons (HashMaps don't support ==)
        else if ((current_left_type == .dict or current_left == .dict) and
            (right_type == .dict or compare.comparators[i] == .dict))
        {
            // For dicts, compare count, all keys match, and all values equal
            const dict_label = self.block_label_counter;
            self.block_label_counter += 1;

            if (op == .NotEq) {
                try self.emit("!");
            }
            try self.output.writer(self.allocator).print("dict_cmp_{d}: {{ const __d1 = (", .{dict_label});
            try genExpr(self, current_left);
            try self.emit("); const __d2 = (");
            try genExpr(self, compare.comparators[i]);
            try self.emit("); if (__d1.count() != __d2.count()) break :dict_cmp_");
            try self.output.writer(self.allocator).print("{d} false; ", .{dict_label});
            try self.emit("var __all_match = true; var __it = __d1.iterator(); ");
            try self.emit("while (__it.next()) |entry| { ");
            try self.emit("if (__d2.get(entry.key_ptr.*)) |v2| { if (!std.meta.eql(entry.value_ptr.*, v2)) { __all_match = false; break; } } ");
            try self.emit("else { __all_match = false; break; } ");
            try self.emit("} ");
            try self.output.writer(self.allocator).print("break :dict_cmp_{d} __all_match; }}", .{dict_label});
        }
        // Handle list comparisons (ArrayList structs don't support ==)
        else if ((current_left_type == .list or current_left == .list) and
            (right_type == .list or compare.comparators[i] == .list))
        {
            // Use std.meta.eql for deep comparison
            // Need to wrap block expressions in parentheses
            const left_needs_wrap = current_left == .list;
            const right_needs_wrap = compare.comparators[i] == .list;

            if (op == .NotEq) {
                try self.emit("!");
            }
            try self.emit("std.meta.eql(");
            if (left_needs_wrap) {
                try self.emit("(");
                try genExpr(self, current_left);
                try self.emit(").items");
            } else {
                try genExpr(self, current_left);
                try self.emit(".items");
            }
            try self.emit(", ");
            if (right_needs_wrap) {
                try self.emit("(");
                try genExpr(self, compare.comparators[i]);
                try self.emit(").items");
            } else {
                try genExpr(self, compare.comparators[i]);
                try self.emit(".items");
            }
            try self.emit(")");
        }
        // Handle set comparisons - sets are HashMaps and don't support direct ==
        else if (@as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type) == .set or
            @as(std.meta.Tag(@TypeOf(right_type)), right_type) == .set)
        {
            // Set comparison: use runtime.setCompare
            // For s == s (identity), both sides are the same HashMap pointer
            if (op == .Eq) {
                try self.emit("runtime.setEqual(");
                try genExpr(self, current_left);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]);
                try self.emit(")");
            } else if (op == .NotEq) {
                try self.emit("!runtime.setEqual(");
                try genExpr(self, current_left);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]);
                try self.emit(")");
            } else {
                // Other comparisons not supported for sets, emit identity check
                try genExpr(self, current_left);
                try self.emit(" == ");
                try genExpr(self, compare.comparators[i]);
            }
        }
        // Handle BigInt or unknown type comparisons (anytype parameters)
        else if (current_left_type == .bigint or right_type == .bigint or
            current_left_type == .unknown or right_type == .unknown)
        {
            // Use runtime.bigIntCompare for safe comparison
            try self.emit("runtime.bigIntCompare(");
            try genExpr(self, current_left);
            try self.emit(", ");
            try genExpr(self, compare.comparators[i]);
            switch (op) {
                .Eq => try self.emit(", .eq)"),
                .NotEq => try self.emit(", .ne)"),
                .Lt => try self.emit(", .lt)"),
                .LtEq => try self.emit(", .le)"),
                .Gt => try self.emit(", .gt)"),
                .GtEq => try self.emit(", .ge)"),
                else => try self.emit(", .eq)"),
            }
        } else {
            // Regular comparisons for non-strings
            // Check for type mismatches between usize and i64
            const left_is_usize = (current_left_type == .usize);
            const left_is_int = (current_left_type == .int);
            const right_is_usize = (right_type == .usize);
            const right_is_int = (right_type == .int);

            // If mixing usize and i64, cast to i64 for comparison
            const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

            // Check if either side is a block expression that needs wrapping
            const left_needs_wrap = producesBlockExpression(current_left);
            const right_needs_wrap = producesBlockExpression(compare.comparators[i]);

            // Cast left operand if needed
            if (left_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            // Wrap block expressions in parentheses
            if (left_needs_wrap) try self.emit("(");
            try genExpr(self, current_left);
            if (left_needs_wrap) try self.emit(")");
            if (left_is_usize and needs_cast) {
                try self.emit("))");
            }

            const op_str = switch (op) {
                .Eq => " == ",
                .NotEq => " != ",
                .Lt => " < ",
                .LtEq => " <= ",
                .Gt => " > ",
                .GtEq => " >= ",
                .Is => " == ",
                .IsNot => " != ",
                else => " ? ",
            };
            try self.emit(op_str);

            // Cast right operand if needed
            if (right_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            // Wrap block expressions in parentheses
            if (right_needs_wrap) try self.emit("(");
            try genExpr(self, compare.comparators[i]);
            if (right_needs_wrap) try self.emit(")");
            if (right_is_usize and needs_cast) {
                try self.emit("))");
            }
        }

        // Close individual comparison paren for chained comparisons
        if (is_chained) {
            try self.emit(")");
        }
    }

    // Close outer paren for chained comparisons
    if (is_chained) {
        try self.emit(")");
    }
}

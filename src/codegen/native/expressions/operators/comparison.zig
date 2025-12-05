/// Comparison operations: ==, !=, <, <=, >, >=, in, not in, is, is not
/// Handles chained comparisons, string comparisons, container membership, identity checks
/// String literal comparisons are folded at compile time ("a" == "a" → true)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const shared = @import("../../shared_maps.zig");
const CompOpStrings = shared.CompOpStrings;

/// Check if expression is a string constant (NOT bytes)
fn isStringConstant(expr: ast.Node) bool {
    if (expr != .constant) return false;
    return expr.constant.value == .string;
}

/// Check if expression is a bytes constant
fn isBytesConstant(expr: ast.Node) bool {
    if (expr != .constant) return false;
    return expr.constant.value == .bytes;
}

/// Extract string content from a constant (strips quotes)
fn getStringContent(s: []const u8) []const u8 {
    if (s.len >= 6 and (std.mem.startsWith(u8, s, "'''") or std.mem.startsWith(u8, s, "\"\"\""))) {
        return s[3 .. s.len - 3];
    } else if (s.len >= 2) {
        return s[1 .. s.len - 1];
    }
    return s;
}

/// Get bytes content from constant
fn getBytesContent(b: []const u8) []const u8 {
    // Bytes literals like b"hello" - strip b prefix and quotes
    if (b.len >= 3 and b[0] == 'b') {
        if (b.len >= 8 and (std.mem.startsWith(u8, b[1..], "'''") or std.mem.startsWith(u8, b[1..], "\"\"\""))) {
            return b[4 .. b.len - 3];
        } else if (b.len >= 3) {
            return b[2 .. b.len - 1];
        }
    }
    return b;
}

/// BigInt comparison operator to enum value mapping
const BigIntCompOps = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Eq", ", .eq)" }, .{ "NotEq", ", .ne)" },
    .{ "Lt", ", .lt)" }, .{ "LtEq", ", .le)" },
    .{ "Gt", ", .gt)" }, .{ "GtEq", ", .ge)" },
});

/// Check if an expression is a call to eval()
fn isEvalCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;
    if (call.func.* != .name) return false;
    return std.mem.eql(u8, call.func.name.id, "eval");
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
/// ALWAYS wraps output in parentheses to prevent Zig chained comparison errors
/// when a compare is used as a sub-expression in another compare
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Always wrap comparison in parentheses to make it safe as a sub-expression
    // This prevents: "False is (x is y)" from generating "false == x == y"
    // which Zig rejects as chained comparison
    try self.emit("(");
    defer self.emit(")") catch {};

    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.inferExprScoped(compare.left.*);

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

        // Special handling for string AND bytes comparisons
        // Both string and bytes need std.mem.eql instead of ==
        // Also handle cases where one side is .unknown (e.g., json.loads) comparing to string
        // AND cases where the literal is a string/bytes but inference got the other side wrong
        const left_is_string = (current_left_type == .string);
        const right_is_string = (right_type == .string);
        // Note: bytes literals are also represented as .string in NativeType, so we
        // only check AST constants for bytes, not NativeType
        const left_is_string_literal = isStringConstant(current_left);
        const right_is_string_literal = isStringConstant(compare.comparators[i]);
        const left_is_bytes_literal = isBytesConstant(current_left);
        const right_is_bytes_literal = isBytesConstant(compare.comparators[i]);
        const either_string = left_is_string or right_is_string or left_is_string_literal or right_is_string_literal;
        const either_bytes = left_is_bytes_literal or right_is_bytes_literal;
        const neither_unknown = (current_left_type != .unknown and right_type != .unknown);

        if ((left_is_string and right_is_string) or (either_string and !neither_unknown) or (left_is_string_literal or right_is_string_literal) or
            either_bytes) {
            // Check for string/bytes literal comparison optimization
            // If both sides are literals, fold at compile time
            const left_is_str_const = isStringConstant(current_left);
            const right_is_str_const = isStringConstant(compare.comparators[i]);
            const left_is_bytes_const = isBytesConstant(current_left);
            const right_is_bytes_const = isBytesConstant(compare.comparators[i]);
            const left_is_const = left_is_str_const or left_is_bytes_const;
            const right_is_const = right_is_str_const or right_is_bytes_const;
            const right_expr = compare.comparators[i];

            switch (op) {
                .Eq => {
                    if (left_is_const and right_is_const) {
                        // Both are string/bytes literals - evaluate at compile time!
                        const left_content = if (left_is_str_const)
                            getStringContent(current_left.constant.value.string)
                        else
                            getBytesContent(current_left.constant.value.bytes);
                        const right_content = if (right_is_str_const)
                            getStringContent(right_expr.constant.value.string)
                        else
                            getBytesContent(right_expr.constant.value.bytes);
                        if (std.mem.eql(u8, left_content, right_content)) {
                            try self.emit("true");
                        } else {
                            try self.emit("false");
                        }
                    } else {
                        // Regular string/bytes comparison
                        try self.emit("std.mem.eql(u8, ");
                        try genExpr(self, current_left);
                        try self.emit(", ");
                        try genExpr(self, right_expr);
                        try self.emit(")");
                    }
                },
                .NotEq => {
                    if (left_is_const and right_is_const) {
                        // Both are string/bytes literals - evaluate at compile time!
                        const left_content = if (left_is_str_const)
                            getStringContent(current_left.constant.value.string)
                        else
                            getBytesContent(current_left.constant.value.bytes);
                        const right_content = if (right_is_str_const)
                            getStringContent(right_expr.constant.value.string)
                        else
                            getBytesContent(right_expr.constant.value.bytes);
                        if (!std.mem.eql(u8, left_content, right_content)) {
                            try self.emit("true");
                        } else {
                            try self.emit("false");
                        }
                    } else {
                        try self.emit("!std.mem.eql(u8, ");
                        try genExpr(self, current_left);
                        try self.emit(", ");
                        try genExpr(self, right_expr);
                        try self.emit(")");
                    }
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
                    try self.emit(CompOpStrings.get(@tagName(op)) orelse " == ");
                    try genExpr(self, compare.comparators[i]);
                },
            }
        }
        // Handle 'in' operator for lists
        else if (op == .In or op == .NotIn) {
            if (right_type == .list) {
                // List membership check using runtime.pyContains for Python semantics
                // Handles NaN identity: NaN in [NaN] == True
                const elem_type = right_type.list.*;
                const type_str = elem_type.toSimpleZigType();

                // For list literals, we need to wrap in a block to access .items
                const is_literal = compare.comparators[i] == .list;

                if (is_literal) {
                    // Wrap the whole thing in a block
                    const list_check_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.output.writer(self.allocator).print("(in_{d}: {{ const __list = ", .{list_check_id});
                    try genExpr(self, compare.comparators[i]); // list literal
                    if (op == .In) {
                        try self.output.writer(self.allocator).print("; break :in_{d} runtime.pyContains({s}, __list.items, ", .{ list_check_id, type_str });
                    } else {
                        try self.output.writer(self.allocator).print("; break :in_{d} !runtime.pyContains({s}, __list.items, ", .{ list_check_id, type_str });
                    }
                    try genExpr(self, current_left); // item to search for
                    try self.emit("); })");
                } else {
                    // For variables, .items access works directly
                    if (op == .In) {
                        try self.emit("(runtime.pyContains(");
                    } else {
                        try self.emit("(!runtime.pyContains(");
                    }
                    try self.emit(type_str);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]); // list variable
                    try self.emit(".items, ");
                    try genExpr(self, current_left); // item to search for
                    try self.emit("))");
                }
            } else if (right_type == .dict) {
                // Dict key check: dict.contains(key)
                // For dict literals, wrap in block to assign to temp var
                const is_literal = compare.comparators[i] == .dict;
                if (is_literal) {
                    const dict_lit = compare.comparators[i].dict;
                    // Empty dict - key in {} is always false, key not in {} is always true
                    if (dict_lit.keys.len == 0) {
                        if (op == .In) {
                            try self.emit("false");
                        } else {
                            try self.emit("true");
                        }
                    } else {
                        // Non-empty dict - check key type to use appropriate contains
                        const key_type = try self.inferExprScoped(dict_lit.keys[0]);
                        const uses_int_keys = key_type == .int;

                        try self.emit("(blk: { const __d = ");
                        try genExpr(self, compare.comparators[i]); // dict literal
                        if (op == .In) {
                            try self.emit("; break :blk __d.contains(");
                        } else {
                            try self.emit("; break :blk !__d.contains(");
                        }
                        if (uses_int_keys) {
                            // Cast to i64 for AutoHashMap key type
                            try self.emit("@as(i64, ");
                            try genExpr(self, current_left); // key
                            try self.emit(")");
                        } else {
                            try genExpr(self, current_left); // key
                        }
                        try self.emit("); })");
                    }
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
                    // For arrays, use &__arr to coerce to slice; for slices, use __arr directly
                    try self.output.writer(self.allocator).print("; const T = std.meta.Elem(@TypeOf(__arr)); const __slice = if (@typeInfo(@TypeOf(__arr)) == .array) &__arr else __arr; break :in_{d} (std.mem.indexOfScalar(T, __slice, __val)", .{in_label_id});
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
                // For anytype parameters (used with None defaults), use comptime type check
                // This handles cases like `expected=None` where expected can be tuple or null
                if (current_left_type == .unknown) {
                    // Emit comptime type check: @TypeOf(x) == @TypeOf(null)
                    if (op == .Is or op == .Eq) {
                        try self.emit("(@TypeOf(");
                        try genExpr(self, current_left);
                        try self.emit(") == @TypeOf(null))");
                    } else {
                        try self.emit("(@TypeOf(");
                        try genExpr(self, current_left);
                        try self.emit(") != @TypeOf(null))");
                    }
                } else {
                    // Generate: var == null (or != null for "is not None")
                    try genExpr(self, current_left);
                    if (op == .Is or op == .Eq) {
                        try self.emit(" == null");
                    } else {
                        try self.emit(" != null");
                    }
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
                    try self.emit(CompOpStrings.get(@tagName(op)) orelse " == ");
                    try genExpr(self, compare.comparators[i]);
                }
            }
        }
        // Handle comparisons involving eval() - returns *PyObject which needs special comparison
        else if (isEvalCall(current_left) or isEvalCall(compare.comparators[i])) {
            // eval() returns *PyObject, need to use runtime comparison functions
            const left_is_eval = isEvalCall(current_left);
            const right_is_eval = isEvalCall(compare.comparators[i]);

            // For == and != with eval() result and integer/bigint, use appropriate comparison
            if (op == .Eq or op == .NotEq) {
                if (op == .NotEq) {
                    try self.emit("!");
                }
                if (left_is_eval and !right_is_eval) {
                    // eval(...) == value - check if value is BigInt
                    // Note: right_type is already in scope from line 103
                    const rhs_tag = @as(std.meta.Tag(@TypeOf(right_type)), right_type);
                    if (rhs_tag == .bigint) {
                        // BigInt comparison
                        try self.emit("runtime.bigIntCompare(runtime.pyObjToBigInt(");
                        try genExpr(self, current_left);
                        try self.emit(", __global_allocator), ");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(", .eq)");
                    } else {
                        // Integer comparison
                        try self.emit("runtime.pyObjEqInt(");
                        try genExpr(self, current_left);
                        try self.emit(", ");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(")");
                    }
                } else if (right_is_eval and !left_is_eval) {
                    // value == eval(...) - check if value is BigInt
                    // Note: current_left_type is already in scope from line 107
                    const lhs_tag = @as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type);
                    if (lhs_tag == .bigint) {
                        // BigInt comparison
                        try self.emit("runtime.bigIntCompare(");
                        try genExpr(self, current_left);
                        try self.emit(", runtime.pyObjToBigInt(");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(", __global_allocator), .eq)");
                    } else {
                        // Integer comparison
                        try self.emit("runtime.pyObjEqInt(");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(", ");
                        try genExpr(self, current_left);
                        try self.emit(")");
                    }
                } else {
                    // Both are eval() calls - compare as PyObject pointers
                    try genExpr(self, current_left);
                    try self.emit(" == ");
                    try genExpr(self, compare.comparators[i]);
                }
            } else {
                // For <, >, <=, >= with eval(), extract int value then compare
                try self.emit("(runtime.pyObjToInt(");
                try genExpr(self, current_left);
                try self.emit(")");
                try self.emit(CompOpStrings.get(@tagName(op)) orelse " == ");
                if (right_is_eval) try self.emit("runtime.pyObjToInt(");
                try genExpr(self, compare.comparators[i]);
                if (right_is_eval) try self.emit(")");
                try self.emit(")");
            }
        }
        // Handle 'is' and 'is not' identity operators
        else if (op == .Is or op == .IsNot) {
            // For arrays/lists/dicts/sets, we need to compare pointers since == doesn't work
            // For class_instances, we use value comparison (they're stack-allocated value types)
            const needs_ptr_compare = current_left_type == .list or right_type == .list or
                current_left_type == .array or right_type == .array or
                current_left_type == .dict or right_type == .dict or
                current_left_type == .set or right_type == .set;

            // Class instances: with heap allocation, both sides are already pointers
            // Direct pointer comparison works for identity semantics
            const is_class_instance = current_left_type == .class_instance or right_type == .class_instance;

            if (is_class_instance) {
                // Both are pointers to heap-allocated objects - direct pointer comparison
                try self.emit("(");
                try genExpr(self, current_left);
                if (op == .Is) {
                    try self.emit(" == ");
                } else {
                    try self.emit(" != ");
                }
                try genExpr(self, compare.comparators[i]);
                try self.emit(")");
            } else if (needs_ptr_compare) {
                // Compare pointers for identity
                // For ArrayList aliases, the alias is a pointer (*ArrayList), so &alias gives **ArrayList
                // For regular variables, &x gives *type
                // We need to compare the actual addresses
                const left_is_alias = if (current_left == .name) self.isArrayListAlias(current_left.name.id) else false;
                const right_is_alias = if (compare.comparators[i] == .name) self.isArrayListAlias(compare.comparators[i].name.id) else false;

                try self.emit("(");
                // For alias: use alias directly (it's already *ArrayList pointing to x)
                // For regular: use &x to get pointer
                if (left_is_alias) {
                    // Alias pointer - use directly
                    try genExpr(self, current_left);
                } else {
                    try self.emit("&");
                    try genExpr(self, current_left);
                }
                if (op == .Is) {
                    try self.emit(" == ");
                } else {
                    try self.emit(" != ");
                }
                if (right_is_alias) {
                    // Alias pointer - use directly
                    try genExpr(self, compare.comparators[i]);
                } else {
                    try self.emit("&");
                    try genExpr(self, compare.comparators[i]);
                }
                try self.emit(")");
            } else {
                // Check if either side is a tuple (struct types don't support ==)
                const left_is_tuple = (@as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type) == .tuple or current_left == .tuple);
                const right_is_tuple = (@as(std.meta.Tag(@TypeOf(right_type)), right_type) == .tuple or compare.comparators[i] == .tuple);

                if (left_is_tuple or right_is_tuple) {
                    // Tuples: for identity comparison ('is'/'is not')
                    // After operations like u += (2,3), variable becomes a slice (from runtime.tupleConcat)
                    // For slices, compare .ptr; for actual tuples, compare &
                    // Use runtime type checking to handle both cases
                    try self.emit("blk: {\n");
                    try self.emit("const __left = ");
                    try genExpr(self, current_left);
                    try self.emit(";\n");
                    try self.emit("const __right = ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(";\n");
                    try self.emit("const __left_ti = @typeInfo(@TypeOf(__left));\n");
                    try self.emit("_ = @typeInfo(@TypeOf(__right));\n");
                    try self.emit("// Different types = different identity for 'is'\n");
                    try self.emit("if (@TypeOf(__left) != @TypeOf(__right)) {\n");
                    if (op == .Is) {
                        try self.emit("break :blk false;\n");
                    } else {
                        try self.emit("break :blk true;\n");
                    }
                    try self.emit("}\n");
                    try self.emit("// Same type - compare addresses\n");
                    try self.emit("if (__left_ti == .pointer and __left_ti.pointer.size == .slice) {\n");
                    // Slices - compare .ptr
                    if (op == .Is) {
                        try self.emit("break :blk __left.ptr == __right.ptr;\n");
                    } else {
                        try self.emit("break :blk __left.ptr != __right.ptr;\n");
                    }
                    try self.emit("} else {\n");
                    // Tuples/structs - compare addresses
                    if (op == .Is) {
                        try self.emit("break :blk &__left == &__right;\n");
                    } else {
                        try self.emit("break :blk &__left != &__right;\n");
                    }
                    try self.emit("}\n");
                    try self.emit("}");
                } else {
                    // For primitives (int, bool, None), identity is same as equality
                    try genExpr(self, current_left);
                    if (op == .Is) {
                        try self.emit(" == ");
                    } else {
                        try self.emit(" != ");
                    }
                    try genExpr(self, compare.comparators[i]);
                }
            }
        }
        // Handle tuple comparisons (anonymous structs don't support ==)
        else if ((@as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type) == .tuple or current_left == .tuple) and
            (@as(std.meta.Tag(@TypeOf(right_type)), right_type) == .tuple or compare.comparators[i] == .tuple))
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
        // Handle class instance comparisons - call __eq__/__ne__/__lt__ etc. methods
        else if (@as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type) == .class_instance or
            @as(std.meta.Tag(@TypeOf(right_type)), right_type) == .class_instance)
        {
            // Class instance comparison - call the appropriate dunder method
            // For ==, call left.__eq__(right) - if it returns NotImplemented, try right.__eq__(left)
            // For !=, call left.__ne__(right) - if not defined, use not left.__eq__(right)
            // Note: Our __eq__/__ne__ return bool (NotImplemented is converted to false in genReturn)

            // Check if left operand is a class instance
            const left_is_class = @as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type) == .class_instance;

            if (left_is_class) {
                // For __ne__, if class doesn't define it, we need to negate __eq__
                if (op == .NotEq) {
                    // Check if class has __ne__
                    const class_name = current_left_type.class_instance;
                    const has_ne = if (self.type_inferrer.class_fields.get(class_name)) |info|
                        info.methods.contains("__ne__")
                    else
                        false;

                    if (!has_ne) {
                        // Use !(a.__eq__(b)) as fallback
                        // Generate: !(runtime.classInstanceEq(a, b))
                        try self.emit("!runtime.classInstanceEq(");
                        try genExpr(self, current_left);
                        try self.emit(", ");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(", __global_allocator)");
                    } else {
                        // Generate: runtime.classInstanceCompare(a, "__ne__", b, allocator)
                        try self.emit("runtime.classInstanceNe(");
                        try genExpr(self, current_left);
                        try self.emit(", ");
                        try genExpr(self, compare.comparators[i]);
                        try self.emit(", __global_allocator)");
                    }
                } else {
                    // Generate: runtime.classInstanceEq(a, b, allocator)
                    // The runtime function will check method signature at comptime
                    try self.emit("runtime.classInstanceEq(");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(", __global_allocator)");
                }
            } else {
                // Right is class instance - use reflected method
                try self.emit("runtime.classInstanceEq(");
                try genExpr(self, compare.comparators[i]);
                try self.emit(", ");
                try genExpr(self, current_left);
                try self.emit(", __global_allocator)");
            }
        }
        // Handle BigInt comparisons
        else if (current_left_type == .bigint or right_type == .bigint) {
            // Use runtime.bigIntCompare for safe comparison
            try self.emit("runtime.bigIntCompare(");
            try genExpr(self, current_left);
            try self.emit(", ");
            try genExpr(self, compare.comparators[i]);
            try self.emit(BigIntCompOps.get(@tagName(op)) orelse ", .eq)");
        }
        // Handle unknown type comparisons (anytype parameters)
        else if (current_left_type == .unknown or right_type == .unknown) {
            // Special case: anytype compared to None
            // For anytype params with default=None, use comptime type check instead of null comparison
            const left_is_none = current_left_type == .none or
                (current_left == .constant and current_left.constant.value == .none);
            const right_is_none = right_type == .none or
                (compare.comparators[i] == .constant and compare.comparators[i].constant.value == .none);

            if (left_is_none or right_is_none) {
                // Emit comptime type check: @TypeOf(x) == @TypeOf(null)
                // This works whether x is null, a tuple, or any other type
                if (op == .Is or op == .Eq) {
                    try self.emit("(@TypeOf(");
                    try genExpr(self, if (left_is_none) compare.comparators[i] else current_left);
                    try self.emit(") == @TypeOf(null))");
                } else {
                    try self.emit("(@TypeOf(");
                    try genExpr(self, if (left_is_none) compare.comparators[i] else current_left);
                    try self.emit(") != @TypeOf(null))");
                }
            } else {
                // Use runtime.bigIntCompare for safe comparison
                try self.emit("runtime.bigIntCompare(");
                try genExpr(self, current_left);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]);
                try self.emit(BigIntCompOps.get(@tagName(op)) orelse ", .eq)");
            }
        } else {
            // Regular comparisons for non-strings
            // Check for type mismatches between usize and i64
            const left_is_usize = (current_left_type == .usize);
            const left_is_int = (current_left_type == .int);
            const right_is_usize = (right_type == .usize);
            const right_is_int = (right_type == .int);
            const left_is_float = (current_left_type == .float);
            const right_is_float = (right_type == .float);
            const left_is_bool = (current_left_type == .bool);
            const right_is_bool = (right_type == .bool);

            // For known primitive types (int, usize, float, bool), use direct comparison
            // For other types (tuples, structs, etc.), use std.meta.eql to avoid Zig struct comparison error
            const both_primitive = (left_is_int or left_is_usize or left_is_float or left_is_bool) and
                (right_is_int or right_is_usize or right_is_float or right_is_bool);

            // If mixing usize and i64, cast to i64 for comparison
            const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

            // Check if either side is a block expression that needs wrapping
            const left_needs_wrap = producesBlockExpression(current_left);
            const right_needs_wrap = producesBlockExpression(compare.comparators[i]);

            // Use std.meta.eql for non-primitive types (tuples, unknown types, etc.)
            if (!both_primitive and (op == .Eq or op == .NotEq)) {
                if (op == .NotEq) try self.emit("!");
                try self.emit("std.meta.eql(");
                if (left_needs_wrap) try self.emit("(");
                try genExpr(self, current_left);
                if (left_needs_wrap) try self.emit(")");
                try self.emit(", ");
                if (right_needs_wrap) try self.emit("(");
                try genExpr(self, compare.comparators[i]);
                if (right_needs_wrap) try self.emit(")");
                try self.emit(")");
            } else {
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

                try self.emit(CompOpStrings.get(@tagName(op)) orelse " ? ");

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

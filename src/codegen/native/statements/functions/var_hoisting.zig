/// Unified Variable Hoisting for Python->Zig Scope Conversion
///
/// Python has function-level scoping - variables assigned anywhere in a function
/// are visible throughout. Zig has block-level scoping - variables in if/for/while/try
/// blocks are not visible outside.
///
/// This module provides a SINGLE SOURCE OF TRUTH for:
/// 1. Detecting if init expressions are safe (no forward references)
/// 2. Inferring fallback types when @TypeOf can't be used
/// 3. Emitting hoisted variable declarations consistently
///
/// Used by both genFunctionBody (top-level functions) and genMethodBody (class methods).
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");
const zig_keywords = @import("zig_keywords");
const scope_analyzer = @import("scope_analyzer.zig");

const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

/// Check if an expression contains a reference to a specific variable name.
/// Used to detect self-references in init expressions (e.g., `line = line.strip()`
/// where `line` is both the target and referenced in the value).
pub fn exprContainsName(expr: *const ast.Node, var_name: []const u8) bool {
    return switch (expr.*) {
        .name => |n| std.mem.eql(u8, n.id, var_name),
        .attribute => |a| exprContainsName(a.value, var_name),
        .call => |c| {
            if (exprContainsName(c.func, var_name)) return true;
            for (c.args) |arg| {
                if (exprContainsNameNode(arg, var_name)) return true;
            }
            for (c.keyword_args) |kwarg| {
                if (exprContainsNameNode(kwarg.value, var_name)) return true;
            }
            return false;
        },
        .binop => |b| exprContainsName(b.left, var_name) or exprContainsName(b.right, var_name),
        .unaryop => |u| exprContainsName(u.operand, var_name),
        .subscript => |s| {
            if (exprContainsName(s.value, var_name)) return true;
            return switch (s.slice) {
                .index => |idx| exprContainsName(idx, var_name),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprContainsName(l, var_name)) return true;
                    if (sl.upper) |u| if (exprContainsName(u, var_name)) return true;
                    if (sl.step) |st| if (exprContainsName(st, var_name)) return true;
                    return false;
                },
            };
        },
        .compare => |cmp| {
            if (exprContainsName(cmp.left, var_name)) return true;
            for (cmp.comparators) |c| {
                if (exprContainsNameNode(c, var_name)) return true;
            }
            return false;
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                if (exprContainsNameNode(elt, var_name)) return true;
            }
            return false;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (exprContainsNameNode(elt, var_name)) return true;
            }
            return false;
        },
        .if_expr => |ie| {
            return exprContainsName(ie.condition, var_name) or
                exprContainsName(ie.body, var_name) or
                exprContainsName(ie.orelse_value, var_name);
        },
        else => false,
    };
}

/// Helper for non-pointer ast.Node
fn exprContainsNameNode(node: ast.Node, var_name: []const u8) bool {
    return switch (node) {
        .name => |n| std.mem.eql(u8, n.id, var_name),
        .attribute => |a| exprContainsName(a.value, var_name),
        .call => |c| {
            if (exprContainsName(c.func, var_name)) return true;
            for (c.args) |arg| {
                if (exprContainsNameNode(arg, var_name)) return true;
            }
            return false;
        },
        .binop => |b| exprContainsName(b.left, var_name) or exprContainsName(b.right, var_name),
        .unaryop => |u| exprContainsName(u.operand, var_name),
        .subscript => |s| exprContainsName(s.value, var_name),
        .constant => false,
        else => false,
    };
}

/// Check if an init expression only references safe variables (no forward refs).
/// Safe means: literals, function parameters, or previously-declared variables.
/// This determines whether we can use @TypeOf(init_expr) safely.
pub fn initExprIsSafe(init: *const ast.Node, safe_vars: *const hashmap_helper.StringHashMap(void)) bool {
    return switch (init.*) {
        // Literals are always safe
        .constant => true,

        // Names are safe if they're in safe_vars (params or already-hoisted)
        .name => |n| safe_vars.contains(n.id),

        // Function calls - check func and all args (including keyword args)
        .call => |c| {
            // Check the function being called
            if (!initExprIsSafe(c.func, safe_vars)) return false;
            // Check all positional arguments
            for (c.args) |arg| {
                if (!initExprIsSafeNode(arg, safe_vars)) return false;
            }
            // Check all keyword arguments
            for (c.keyword_args) |kwarg| {
                if (!initExprIsSafeNode(kwarg.value, safe_vars)) return false;
            }
            return true;
        },

        // Binary operations - check both sides
        .binop => |b| initExprIsSafe(b.left, safe_vars) and initExprIsSafe(b.right, safe_vars),

        // Unary operations - check operand
        .unaryop => |u| initExprIsSafe(u.operand, safe_vars),

        // Attribute access - check the value
        .attribute => |a| initExprIsSafe(a.value, safe_vars),

        // Subscript - check value and index
        .subscript => |s| {
            if (!initExprIsSafe(s.value, safe_vars)) return false;
            return switch (s.slice) {
                .index => |idx| initExprIsSafe(idx, safe_vars),
                .slice => |sl| {
                    if (sl.lower) |l| if (!initExprIsSafe(l, safe_vars)) return false;
                    if (sl.upper) |u| if (!initExprIsSafe(u, safe_vars)) return false;
                    if (sl.step) |st| if (!initExprIsSafe(st, safe_vars)) return false;
                    return true;
                },
            };
        },

        // Comparisons - check all parts
        .compare => |cmp| {
            if (!initExprIsSafe(cmp.left, safe_vars)) return false;
            for (cmp.comparators) |c| {
                if (!initExprIsSafeNode(c, safe_vars)) return false;
            }
            return true;
        },

        // Tuples and lists - check all elements
        .tuple => |t| {
            for (t.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },

        // If expression - check all three parts
        .if_expr => |ie| {
            return initExprIsSafe(ie.condition, safe_vars) and
                initExprIsSafe(ie.body, safe_vars) and
                initExprIsSafe(ie.orelse_value, safe_vars);
        },

        // Conservative default: assume unsafe for unknown node types
        else => false,
    };
}

/// Helper for non-pointer ast.Node
fn initExprIsSafeNode(node: ast.Node, safe_vars: *const hashmap_helper.StringHashMap(void)) bool {
    return switch (node) {
        .constant => true,
        .name => |n| safe_vars.contains(n.id),
        .call => |c| {
            if (!initExprIsSafe(c.func, safe_vars)) return false;
            for (c.args) |arg| {
                if (!initExprIsSafeNode(arg, safe_vars)) return false;
            }
            for (c.keyword_args) |kwarg| {
                if (!initExprIsSafeNode(kwarg.value, safe_vars)) return false;
            }
            return true;
        },
        .binop => |b| initExprIsSafe(b.left, safe_vars) and initExprIsSafe(b.right, safe_vars),
        .unaryop => |u| initExprIsSafe(u.operand, safe_vars),
        .attribute => |a| initExprIsSafe(a.value, safe_vars),
        .tuple => |t| {
            for (t.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        else => false,
    };
}

/// Infer a fallback type when @TypeOf can't be used due to forward references.
/// This provides a reasonable default based on the expression shape and source context.
pub fn inferFallbackType(init: ?*const ast.Node, source: scope_analyzer.EscapedSource) []const u8 {
    if (init) |expr| {
        return switch (expr.*) {
            // Function calls - usually return PyValue or objects
            .call => |c| {
                // Check for known return types
                if (c.func.* == .name) {
                    const fn_name = c.func.name.id;
                    // eval() returns *PyObject
                    if (std.mem.eql(u8, fn_name, "eval")) {
                        return "*runtime.PyObject";
                    }
                    // float() returns f64
                    if (std.mem.eql(u8, fn_name, "float")) {
                        return "f64";
                    }
                    // int() returns i64
                    if (std.mem.eql(u8, fn_name, "int")) {
                        return "i64";
                    }
                    // bool() returns bool
                    if (std.mem.eql(u8, fn_name, "bool")) {
                        return "bool";
                    }
                    // bytes/bytearray calls return []const u8
                    if (std.mem.eql(u8, fn_name, "bytes") or
                        std.mem.eql(u8, fn_name, "bytearray"))
                    {
                        return "[]const u8";
                    }
                    // String functions
                    if (std.mem.eql(u8, fn_name, "str")) {
                        return "[]const u8";
                    }
                    // Range returns iterator
                    if (std.mem.eql(u8, fn_name, "range")) {
                        return "[]i64";
                    }
                }
                // Generic function call - use PyValue
                return "runtime.PyValue";
            },

            // Literals have known types
            .constant => |c| switch (c.value) {
                .int => "i64",
                .float => "f64",
                .string => "[]const u8",
                .bytes => "runtime.builtins.PyBytes",
                .bool => "bool",
                .none => "?*anyopaque",
                else => "runtime.PyValue",
            },

            // Collection types
            .list => "std.ArrayList(runtime.PyValue)",
            .tuple => "runtime.PyValue",
            .dict => "runtime.PyValue",

            // Binary ops usually produce same type as operands
            .binop => |b| {
                // If either side is a string op, result is string
                if (b.left.* == .constant and b.left.constant.value == .string) {
                    return "[]const u8";
                }
                // Python's / operator ALWAYS returns float (true division)
                if (b.op == .Div) {
                    return "f64";
                }
                // If either operand is float, result is float
                if (b.left.* == .constant and b.left.constant.value == .float) {
                    return "f64";
                }
                if (b.right.* == .constant and b.right.constant.value == .float) {
                    return "f64";
                }
                return "i64"; // Default for other numeric ops
            },

            // Subscript/slice operations - check what we're slicing
            .subscript => |s| {
                // String slices return strings
                if (s.value.* == .name or s.value.* == .constant) {
                    // Check if base is a string literal or known string var
                    if (s.value.* == .constant and s.value.constant.value == .string) {
                        return "[]const u8";
                    }
                    // For slices (a[1:] or a[1:2]), assume string for now
                    if (s.slice == .slice) {
                        return "[]const u8";
                    }
                }
                return "runtime.PyValue";
            },

            // Attribute access - usually returns PyValue
            .attribute => "runtime.PyValue",

            // If expression - complex, use PyValue
            .if_expr => "runtime.PyValue",

            // Default
            else => "runtime.PyValue",
        };
    }

    // No init expr - base on source context
    // Use runtime.PyValue as universal fallback since we don't know the actual type
    // For for_loop, tuple unpacking can have string or int elements - PyValue handles both
    return switch (source) {
        .try_except => "runtime.PyValue",
        .for_loop => "runtime.PyValue", // Tuple elements can be any type
        .if_stmt => "runtime.PyValue",
        .with_stmt => "runtime.PyValue",
    };
}

/// Emit hoisted variable declarations at function/method start.
/// This is the SINGLE SOURCE OF TRUTH for hoisting - called from both
/// genFunctionBody and genMethodBody.
///
/// Strategy:
/// 1. Build safe_vars set from function parameters
/// 2. For each escaped var:
///    - If init_expr is safe (no forward refs), use @TypeOf(init_expr)
///    - Otherwise, use inferred fallback type
/// 3. Add each declared var to safe_vars for subsequent vars
pub fn emitHoistedDeclarations(
    self: *NativeCodegen,
    escaped_vars: []const scope_analyzer.EscapedVar,
    func_params: []const ast.Arg,
) CodegenError!void {
    if (escaped_vars.len == 0) return;

    // Build safe vars set from function parameters
    var safe_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer safe_vars.deinit();

    for (func_params) |param| {
        try safe_vars.put(param.name, {});
    }

    // Also add module-level names as safe (they're always available)
    var mod_iter = self.module_level_funcs.iterator();
    while (mod_iter.next()) |entry| {
        try safe_vars.put(entry.key_ptr.*, {});
    }

    // Add module-level variable names (tracked explicitly during module generation)
    var mod_var_iter = self.module_level_vars.iterator();
    while (mod_var_iter.next()) |entry| {
        try safe_vars.put(entry.key_ptr.*, {});
    }

    // Emit each hoisted variable declaration
    for (escaped_vars) |escaped| {
        // Skip variables that match function parameters - they're already declared
        var is_param = false;
        for (func_params) |param| {
            if (std.mem.eql(u8, escaped.name, param.name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;

        // Skip module-level functions - they're already declared as functions
        // Python allows `genslices = rslices` to reassign function names,
        // but in Zig the function is already defined so we skip hoisting
        if (self.module_level_funcs.contains(escaped.name)) continue;

        // Also skip variables that are assigned a module-level function
        // e.g., `permutations = rpermutation` - can't hoist a function reference
        if (escaped.init_expr) |init| {
            if (init.* == .name) {
                if (self.module_level_funcs.contains(init.name.id)) continue;
            }
        }

        // For loop target variables ARE hoisted - they need to persist after the loop.
        // The for loop codegen checks hoisted_vars and uses assignment instead of const.
        // Don't skip them here.

        // Check if this hoisted var would shadow a module-level pre-declared global
        // If so, rename the local to avoid Zig's shadowing error
        var actual_name = escaped.name;
        if (self.module_level_vars.contains(escaped.name)) {
            const shadow_name = try std.fmt.allocPrint(self.allocator, "{s}_local", .{escaped.name});
            try self.var_renames.put(try self.allocator.dupe(u8, escaped.name), shadow_name);
            actual_name = shadow_name;
        }

        try self.emitIndent();
        try self.emit("var ");
        // Use writeLocalVarName to be consistent with expression usage
        // This handles both keyword escaping AND method shadowing (e.g., "format" -> "format_")
        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);

        if (escaped.init_expr) |init| {
            // Check for self-reference: `line = line.strip()` where init references the variable being declared
            // This would cause circular reference in @TypeOf - use fallback type instead
            const has_self_reference = exprContainsName(init, escaped.name);

            if (!has_self_reference and initExprIsSafe(init, &safe_vars)) {
                // Safe to use @TypeOf - no forward references and no self-references
                try self.emit(": @TypeOf(");
                try self.genExpr(init.*);
                try self.emit(")");
            } else {
                // Has forward refs or self-reference - use fallback type
                const fallback = inferFallbackType(init, escaped.source);
                try self.emit(": ");
                try self.emit(fallback);
            }
        } else if (escaped.source == .for_loop and escaped.for_iter_expr != null and escaped.tuple_index != null) {
            // For-loop tuple unpacking: derive type from iteration expression
            // But only if the iter expression uses safe names (params, globals)
            // Otherwise fall back to runtime.PyValue to avoid forward reference errors
            const iter_safe = initExprIsSafe(escaped.for_iter_expr.?, &safe_vars);
            if (iter_safe) {
                // Generate: var s: @TypeOf(L.items[0].@"0") = undefined;
                try self.emit(": @TypeOf((");
                try self.genExpr(escaped.for_iter_expr.?.*);
                // Add .items if it's an ArrayList (list type)
                const iter_type = self.type_inferrer.inferExpr(escaped.for_iter_expr.?.*) catch .unknown;
                if (iter_type == .list) {
                    try self.emit(").items[0].@\"");
                } else {
                    // For other types (tuples, etc.) access directly
                    try self.emit(")[0].@\"");
                }
                try self.output.writer(self.allocator).print("{d}\")", .{escaped.tuple_index.?});
            } else {
                // Iter expression uses local vars - use fallback type
                const fallback = inferFallbackType(null, escaped.source);
                try self.emit(": ");
                try self.emit(fallback);
            }
        } else {
            // No init expr - use fallback based on source
            const fallback = inferFallbackType(null, escaped.source);
            try self.emit(": ");
            try self.emit(fallback);
        }

        try self.emit(" = undefined;\n");
        // Add discard to prevent "unused variable" errors when body is skipped
        try self.emitIndent();
        try self.emit("_ = &");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), escaped.name);
        try self.emit(";\n");

        // Add this var to safe_vars for subsequent hoisted vars
        try safe_vars.put(escaped.name, {});
    }
}

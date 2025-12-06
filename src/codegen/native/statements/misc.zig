/// Miscellaneous statement code generation (return, import, assert, global, del, raise)
const std = @import("std");
const ast = @import("ast");
const zig_keywords = @import("zig_keywords");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const shared = @import("../shared_maps.zig");
const ExceptionTypes = shared.RuntimeExceptions;
const var_hoisting = @import("functions/var_hoisting.zig");
const scope_analyzer = @import("functions/scope_analyzer.zig");
const hashmap_helper = @import("hashmap_helper");

// Re-export print statement generation
pub const genPrint = @import("print.zig").genPrint;

/// Check if a return value is a tail-recursive call to the current function
/// A tail call is: return func_name(args) where func_name == current function
fn isTailRecursiveCall(self: *NativeCodegen, value: ast.Node) ?ast.Node.Call {
    // Must be inside a function
    const current_func = self.current_function_name orelse return null;

    // Must be a call expression
    if (value != .call) return null;
    const call = value.call;

    // Function must be a simple name (not attribute/method call)
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Must be calling the current function
    if (!std.mem.eql(u8, func_name, current_func)) return null;

    return call;
}

/// Magic method return conversion info
const MagicMethodConversion = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Get conversion wrapper for magic method return values
/// Some dunder methods have fixed return types that require conversion
fn getMagicMethodConversion(method_name: []const u8) ?MagicMethodConversion {
    const converters = std.StaticStringMap(MagicMethodConversion).initComptime(.{
        // Python 3: __bool__ must return exactly bool, not converted from other types
        .{ "__bool__", MagicMethodConversion{ .prefix = "runtime.validateBoolReturn(", .suffix = ")" } },
        // Use runtime.pyToInt for __len__/__hash__/__int__/__index__ to handle both int and PyValue
        .{ "__len__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__hash__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__int__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__index__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__float__", MagicMethodConversion{ .prefix = "runtime.toFloat(", .suffix = ")" } },
    });
    return converters.get(method_name);
}

/// Comparison magic methods that return bool
const ComparisonMagicMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__eq__", {} },
    .{ "__ne__", {} },
    .{ "__lt__", {} },
    .{ "__le__", {} },
    .{ "__gt__", {} },
    .{ "__ge__", {} },
});

/// Generate return statement with tail-call optimization
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    // Emit pending discards BEFORE the return statement
    // This handles unused local variables in closures that return early
    // e.g., def f(): msg = "..."; return self.assertRaisesRegex(...) -> msg unused
    try self.emitPendingDiscards();

    // Mark control flow as terminated on any exit path
    defer self.control_flow_terminated = true;

    try self.emitIndent();

    if (ret.value) |value| {
        // Check if returning NotImplemented from a comparison method
        // In Python, comparison methods can return NotImplemented to signal fallback
        // But in our compiled code, these methods return bool, so convert to false
        if (value.* == .name and std.mem.eql(u8, value.name.id, "NotImplemented")) {
            if (self.current_function_name) |fn_name| {
                if (ComparisonMagicMethods.has(fn_name)) {
                    try self.emit("return false;\n");
                    return;
                }
            }
        }

        // Check if returning a pre-generated closure (e.g., return with_metaclass where with_metaclass is a nested function)
        if (value.* == .name) {
            const name = value.name.id;
            if (self.pending_closure_types.get(name)) |type_name| {
                // Return an instance of the pre-generated closure type
                try self.output.writer(self.allocator).print("return {s}{{}};\n", .{type_name});
                return;
            }
        }

        // Check for tail-recursive call
        if (isTailRecursiveCall(self, value.*)) |call| {
            // Emit: return @call(.always_tail, func_name, .{args})
            try self.emit("return @call(.always_tail, ");
            try self.emit(call.func.name.id);
            try self.emit(", .{");

            // Generate arguments
            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(arg);
            }

            try self.emit("});\n");
            return;
        }

        // Normal return - check if inside a magic method that needs conversion
        try self.emit("return ");

        // Check if returning self from a method (with either *@This() or *const @This())
        // When method signature returns !@This() and we return self,
        // we need: return __self.*; (dereference the pointer)
        // This applies to both mutable (*@This()) and immutable (*const @This()) methods
        const is_self_return = self.current_class_name != null and
            value.* == .name and
            std.mem.eql(u8, value.name.id, "self");
        // For methods that return self, always dereference when inside a nested method
        // (where self is renamed to __self) or when method_self_is_mutable
        const needs_self_deref = is_self_return and (self.method_self_is_mutable or self.method_nesting_depth > 0);

        // Check if we're inside a magic method that needs return value conversion
        const conversion = if (self.current_function_name) |fn_name|
            getMagicMethodConversion(fn_name)
        else
            null;

        // Magic method conversion ALWAYS takes precedence (e.g., __bool__ must validate return type)
        if (conversion) |conv| {
            try self.emit(conv.prefix);
            if (needs_self_deref) {
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
                if (current_class_is_nested) {
                    try self.emit(self_name);
                } else {
                    try self.output.writer(self.allocator).print("{s}.*", .{self_name});
                }
            } else {
                try self.genExpr(value.*);
            }
            try self.emit(conv.suffix);
        } else if (needs_self_deref) {
            // For nested classes, return the pointer directly
            // since init() returns *@This() and methods returning self also return *@This()
            // For top-level classes, dereference to return @This() value
            const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
            const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
            if (current_class_is_nested) {
                // Nested class: return pointer directly
                try self.emit(self_name);
            } else {
                // Top-level class: dereference to get value
                try self.output.writer(self.allocator).print("{s}.*", .{self_name});
            }
        } else {
            try self.genExpr(value.*);
        }
    } else {
        try self.emit("return ");
    }
    try self.emit(";\n");
}

/// Generate import statement: import module
/// For module-level imports, this is handled in PHASE 3
/// For local imports (inside functions), we need to generate const bindings
pub fn genImport(self: *NativeCodegen, import: ast.Node.Import) CodegenError!void {
    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3 of generator.zig
    // In module mode, indent_level == 1 means we're at struct level (still module-level)
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    const module_name = import.module;
    const alias = import.asname orelse module_name;

    // Look up in registry
    if (self.import_registry.lookup(module_name)) |info| {
        // Skip generating local import if the module is a well-known module
        // that's typically imported at module level - Python allows redundant imports
        // but Zig doesn't allow shadowing
        // Note: This is a heuristic - we skip stdlib modules since they're usually
        // imported at module level and would cause shadowing errors
        if (info.strategy == .zig_runtime) {
            return;
        }

        if (info.zig_import) |zig_import| {
            try self.emitIndent();
            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias);
            try self.emit(" = ");
            try self.emit(zig_import);
            try self.emit(";\n");
        }
    }
}

/// Generate from-import statement: from module import names
/// Module-level imports are handled in PHASE 3 of generator.zig
/// Local imports (inside functions) need to generate const bindings
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    const module_name = import.module;

    // Look up in registry to get the Zig module path
    if (self.import_registry.lookup(module_name)) |info| {
        if (info.zig_import) |zig_import| {
            // Generate const bindings for each imported name
            // from random import getrandbits -> const getrandbits = runtime.random.getrandbits;
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                // Skip if already declared at module level (avoids shadowing error)
                // This happens when the same import appears both at module level and locally
                if (self.isDeclared(alias) or self.module_level_from_imports.contains(alias)) {
                    continue;
                }

                try self.emitIndent();
                try self.emit("const ");
                try self.emit(alias);
                try self.emit(" = ");
                try self.emit(zig_import);
                try self.emit(".");
                try self.emit(name);
                try self.emit(";\n");
            }
        } else {
            // Module uses inline codegen (e.g., random) - track symbols for dispatch
            // from random import getrandbits -> record "getrandbits" -> "random"
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                try self.local_from_imports.put(alias, module_name);
            }
        }
    }
}

/// Generate global statement
/// The global statement itself doesn't emit code - it just marks variables as global
/// so that subsequent assignments reference the outer scope variable instead of creating a new one
pub fn genGlobal(self: *NativeCodegen, global_node: ast.Node.GlobalStmt) CodegenError!void {
    // Mark each variable as global
    for (global_node.names) |name| {
        try self.markGlobalVar(name);
    }
    // No code emitted - this is a directive, not an executable statement
}

/// Generate del statement
/// Handles: del dict[key] -> dict.remove(key)
///          del list[idx] -> list orderedRemove
///          del var -> no-op (variable scope, memory hint)
pub fn genDel(self: *NativeCodegen, del_node: ast.Node.Del) CodegenError!void {
    for (del_node.targets) |target| {
        try self.emitIndent();
        switch (target) {
            .subscript => |sub| {
                // del dict[key] or del list[idx]
                // Generate: _ = dict.fetchSwapRemove(key) or _ = list.orderedRemove(idx)
                switch (sub.slice) {
                    .index => |idx| {
                        // Check if it's a list (ArrayList) or dict
                        const container_type = try self.inferExprScoped(sub.value.*);
                        const is_list = container_type == .list or container_type == .array or
                            (sub.value.* == .name and self.isArrayListVar(sub.value.name.id));

                        try self.emit("_ = ");
                        try self.genExpr(sub.value.*);

                        if (is_list) {
                            // For lists, use orderedRemove which preserves order
                            // Need to normalize negative indices: if idx < 0, use len + idx
                            try self.emit(".orderedRemove(blk: { const __idx = ");
                            try self.genExpr(idx.*);
                            try self.emit("; const __len = ");
                            try self.genExpr(sub.value.*);
                            try self.emit(".items.len; break :blk if (__idx < 0) @as(usize, @intCast(@as(i64, @intCast(__len)) + __idx)) else @as(usize, @intCast(__idx)); });\n");
                        } else {
                            // For dicts, use fetchSwapRemove (returns removed value or null)
                            try self.emit(".fetchSwapRemove(");
                            try self.genExpr(idx.*);
                            try self.emit(");\n");
                        }
                    },
                    .slice => |slice| {
                        // del list[a:b] - delete elements from a to b
                        // Use replaceRange with empty slice to remove elements
                        try self.emit("{\n");
                        self.indent();

                        // Get list reference - handle ArrayList aliases
                        try self.emitIndent();
                        try self.emit("const __list = ");
                        if (sub.value.* == .name) {
                            const var_name = sub.value.name.id;
                            if (self.isArrayListAlias(var_name)) {
                                // Alias is already a pointer, just use it directly
                                try self.genExpr(sub.value.*);
                            } else {
                                // Regular ArrayList, take address
                                try self.emit("&");
                                try self.genExpr(sub.value.*);
                            }
                        } else {
                            try self.emit("&");
                            try self.genExpr(sub.value.*);
                        }
                        try self.emit(";\n");

                        // Calculate start index
                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emit("const __start: usize = @intCast(");
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __start: usize = 0;\n");
                        }

                        // Calculate end index
                        try self.emitIndent();
                        if (slice.upper) |upper| {
                            try self.emit("const __end: usize = @intCast(");
                            try self.genExpr(upper.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __end: usize = __list.items.len;\n");
                        }

                        // Replace slice with empty slice to delete elements
                        // replaceRange(allocator, start, length, replacement)
                        try self.emitIndent();
                        try self.emit("const __empty: [0]@TypeOf(__list.items[0]) = .{};\n");
                        try self.emitIndent();
                        try self.emit("__list.replaceRange(__global_allocator, __start, __end - __start, &__empty) catch {};\n");

                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    },
                }
            },
            .attribute => |attr| {
                // del obj.attr - no-op in compiled code (would need dynamic attr deletion)
                try self.emit("// del ");
                try self.genExpr(attr.value.*);
                try self.emit(".");
                try self.emit(attr.attr);
                try self.emit(" (no-op in AOT)\n");
            },
            .name => {
                // del var - just a memory hint in Python, no-op in compiled code
                try self.emit("// del ");
                try self.emit(target.name.id);
                try self.emit(" (no-op in AOT)\n");
            },
            else => {
                // Unsupported target type
                try self.emit("// del statement (no-op in AOT)\n");
            },
        }
    }
}

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!runtime.toBool(condition)) { runtime.debug_reader.printPythonError(...); std.debug.panic(...); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    // Record line mapping for debug info (maps Python assert line -> Zig line)
    self.recordAssertLineMapping();

    // Check if condition is a simple bool type that doesn't need toBool wrapper
    const cond_type = self.inferExprScoped(assert_node.condition.*) catch .unknown;
    const is_simple_bool = cond_type == .bool;

    try self.emitIndent();
    if (is_simple_bool) {
        // Direct negation for bool expressions
        try self.emit("if (!(");
        try self.genExpr(assert_node.condition.*);
        try self.emit(")) {\n");
    } else {
        // Use runtime.toBool for proper Python truthiness (lists, strings, etc.)
        try self.emit("if (!runtime.toBool(");
        try self.genExpr(assert_node.condition.*);
        try self.emit(")) {\n");
    }

    self.indent();

    // Print Python-style error traceback before panic
    try self.emitIndent();
    if (assert_node.msg) |msg| {
        // assert x, "message"
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", ");
        // Generate message expression - if it's a string literal, emit directly
        if (msg.* == .constant and msg.constant.value == .string) {
            try self.emit("\"");
            try self.emit(msg.constant.value.string);
            try self.emit("\"");
        } else {
            // For non-string messages, convert to string representation
            try self.emit("\"assertion failed\"");
        }
        try self.emit(", @src().line);\n");
        try self.emitIndent();
        try self.emit("std.debug.panic(\"AssertionError: {any}\", .{");
        try self.genExpr(msg.*);
        try self.emit("});\n");
    } else {
        // assert x
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"AssertionError\", \"assertion failed\", @src().line);\n");
        try self.emitIndent();
        try self.emit("std.debug.panic(\"AssertionError\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}


/// Check if a variable name is used in an expression
fn exprUsesVar(expr: ast.Node, var_name: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, var_name),
        .attribute => |a| exprUsesVar(a.value.*, var_name),
        .subscript => |s| blk: {
            if (exprUsesVar(s.value.*, var_name)) break :blk true;
            switch (s.slice) {
                .index => |idx| break :blk exprUsesVar(idx.*, var_name),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprUsesVar(l.*, var_name)) break :blk true;
                    if (sl.upper) |u| if (exprUsesVar(u.*, var_name)) break :blk true;
                    if (sl.step) |st| if (exprUsesVar(st.*, var_name)) break :blk true;
                    break :blk false;
                },
            }
        },
        .call => |c| blk: {
            if (exprUsesVar(c.func.*, var_name)) break :blk true;
            for (c.args) |arg| {
                if (exprUsesVar(arg, var_name)) break :blk true;
            }
            for (c.keyword_args) |kw| {
                if (exprUsesVar(kw.value, var_name)) break :blk true;
            }
            break :blk false;
        },
        .binop => |b| exprUsesVar(b.left.*, var_name) or exprUsesVar(b.right.*, var_name),
        .unaryop => |u| exprUsesVar(u.operand.*, var_name),
        .boolop => |b| blk: {
            for (b.values) |v| {
                if (exprUsesVar(v, var_name)) break :blk true;
            }
            break :blk false;
        },
        .compare => |c| blk: {
            if (exprUsesVar(c.left.*, var_name)) break :blk true;
            for (c.comparators) |comp| {
                if (exprUsesVar(comp, var_name)) break :blk true;
            }
            break :blk false;
        },
        .if_expr => |i| exprUsesVar(i.condition.*, var_name) or exprUsesVar(i.body.*, var_name) or exprUsesVar(i.orelse_value.*, var_name),
        .list => |l| blk: {
            for (l.elts) |e| {
                if (exprUsesVar(e, var_name)) break :blk true;
            }
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| {
                if (exprUsesVar(e, var_name)) break :blk true;
            }
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| {
                if (exprUsesVar(k, var_name)) break :blk true;
            }
            for (d.values) |v| {
                if (exprUsesVar(v, var_name)) break :blk true;
            }
            break :blk false;
        },
        .fstring => |f| blk: {
            for (f.parts) |p| {
                switch (p) {
                    .expr => |e| if (exprUsesVar(e.node.*, var_name)) break :blk true,
                    .format_expr => |fe| if (exprUsesVar(fe.expr.*, var_name)) break :blk true,
                    .conv_expr => |ce| if (exprUsesVar(ce.expr.*, var_name)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        .lambda => |l| exprUsesVar(l.body.*, var_name),
        .starred => |s| exprUsesVar(s.value.*, var_name),
        .double_starred => |ds| exprUsesVar(ds.value.*, var_name),
        else => false,
    };
}

/// Check if a variable name is used in a statement
fn stmtUsesVar(stmt: ast.Node, var_name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesVar(e.value.*, var_name),
        .assign => |a| blk: {
            if (exprUsesVar(a.value.*, var_name)) break :blk true;
            for (a.targets) |t| {
                if (exprUsesVar(t, var_name)) break :blk true;
            }
            break :blk false;
        },
        .aug_assign => |a| exprUsesVar(a.target.*, var_name) or exprUsesVar(a.value.*, var_name),
        .if_stmt => |i| blk: {
            if (exprUsesVar(i.condition.*, var_name)) break :blk true;
            for (i.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            for (i.else_body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (exprUsesVar(f.iter.*, var_name)) break :blk true;
            for (f.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (exprUsesVar(w.condition.*, var_name)) break :blk true;
            for (w.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .return_stmt => |r| if (r.value) |v| exprUsesVar(v.*, var_name) else false,
        .with_stmt => |w| blk: {
            if (exprUsesVar(w.context_expr.*, var_name)) break :blk true;
            for (w.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if a variable is used in a list of statements
fn varUsedInStatements(body: []const ast.Node, var_name: []const u8) bool {
    for (body) |stmt| {
        if (stmtUsesVar(stmt, var_name)) return true;
    }
    return false;
}

/// Check if with expression is a unittest context manager that should be skipped
/// Check if context manager is assertRaises or assertRaisesRegex (needs error handling)
/// Also handles tuples of context managers (e.g., with (assertRaises(), Stopwatch()) as ...)
fn isAssertRaisesContext(expr: ast.Node) bool {
    // Direct call to self.assertRaises or self.assertRaisesRegex
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name) {
                const obj_name = attr.value.name.id;
                if (std.mem.eql(u8, obj_name, "self")) {
                    const method_name = attr.attr;
                    if (std.mem.eql(u8, method_name, "assertRaises") or
                        std.mem.eql(u8, method_name, "assertRaisesRegex"))
                    {
                        return true;
                    }
                }
            }
        }
    }
    // Tuple of context managers - check if any element is assertRaises
    // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
    if (expr == .tuple) {
        for (expr.tuple.elts) |elt| {
            // Handle named expression (context manager as var)
            const actual_expr = if (elt == .named_expr) elt.named_expr.value.* else elt;
            if (isAssertRaisesContext(actual_expr)) {
                return true;
            }
        }
    }
    return false;
}

fn isUnittestContextManager(expr: ast.Node) bool {
    // Check for self.assertWarns(...), self.assertRaises(...), self.assertRaisesRegex(...), etc.
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            // Check for self.method() pattern
            if (attr.value.* == .name) {
                const obj_name = attr.value.name.id;
                if (std.mem.eql(u8, obj_name, "self")) {
                    // Check for unittest context manager methods
                    const method_name = attr.attr;
                    if (std.mem.eql(u8, method_name, "assertWarns") or
                        std.mem.eql(u8, method_name, "assertRaises") or
                        std.mem.eql(u8, method_name, "assertRaisesRegex") or
                        std.mem.eql(u8, method_name, "assertLogs") or
                        std.mem.eql(u8, method_name, "subTest"))
                    {
                        return true;
                    }
                }
            }
        }
    }
    // Tuple of context managers - check if any element is a unittest context manager
    // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
    if (expr == .tuple) {
        for (expr.tuple.elts) |elt| {
            // Handle named expression (context manager as var)
            const actual_expr = if (elt == .named_expr) elt.named_expr.value.* else elt;
            if (isUnittestContextManager(actual_expr)) {
                return true;
            }
        }
    }
    return false;
}

/// Recursively hoist variables from with statement body
/// This handles both direct assignments and nested with statements
/// Uses @TypeOf(init_expr) for comptime type inference instead of guessing
fn hoistWithBodyVars(self: *NativeCodegen, body: []const ast.Node) CodegenError!void {
    hoistWithBodyVarsSkipping(self, body, null) catch {};
}

/// Internal helper that tracks for-loop target to skip hoisting reassignments
fn hoistWithBodyVarsSkipping(self: *NativeCodegen, body: []const ast.Node, skip_var: ?[]const u8) CodegenError!void {
    for (body) |stmt| {
        if (stmt == .assign) {
            if (stmt.assign.targets.len > 0) {
                const target = stmt.assign.targets[0];
                if (target == .name) {
                    const var_name = target.name.id;
                    // Skip hoisting if this is a reassignment of the for-loop variable
                    // e.g., `for line in file: line = line.strip()` - don't hoist line
                    if (skip_var) |skip| {
                        if (std.mem.eql(u8, var_name, skip)) continue;
                    }
                    // Use @TypeOf(value_expr) for proper type inference
                    try hoistVarWithExpr(self, var_name, stmt.assign.value);
                }
            }
        } else if (stmt == .with_stmt) {
            // Nested with statement - hoist its variable if it has one (only simple name targets)
            if (stmt.with_stmt.optional_vars) |target| {
                if (target.* == .name) {
                    const var_name = target.name.id;
                    if (isUnittestContextManager(stmt.with_stmt.context_expr.*)) {
                        // Unittest context managers need hoisting too - err may be used after with block
                        // Skip if already hoisted or declared (handles multiple with assertRaises as err)
                        if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
                            // Hoist as ContextManager type - use const since it's only assigned once
                            // Check for module-level function shadowing
                            const shadows_module_func = self.module_level_funcs.contains(var_name);
                            var actual_name = var_name;
                            if (shadows_module_func and !self.var_renames.contains(var_name)) {
                                const prefixed_name = try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ var_name, self.lambda_counter });
                                self.lambda_counter += 1;
                                try self.var_renames.put(var_name, prefixed_name);
                                actual_name = prefixed_name;
                            } else if (self.var_renames.get(var_name)) |renamed| {
                                actual_name = renamed;
                            }
                            try self.emitIndent();
                            try self.emit("const ");
                            try self.emit(actual_name);
                            try self.emit(": runtime.unittest.ContextManager = runtime.unittest.ContextManager{};\n");
                            try self.hoisted_vars.put(var_name, {});
                        }
                    } else {
                        // Use @TypeOf(context_expr) for comptime type inference
                        try hoistVarWithExpr(self, var_name, stmt.with_stmt.context_expr);
                    }
                }
            }
            // Handle tuple context managers with named expressions
            if (stmt.with_stmt.context_expr.* == .tuple) {
                for (stmt.with_stmt.context_expr.tuple.elts) |elt| {
                    if (elt == .named_expr) {
                        const named = elt.named_expr;
                        const cm_var_name = named.target.name.id;
                        const cm_expr = named.value.*;
                        if (isUnittestContextManager(cm_expr)) {
                            // Hoist unittest context manager variable - use const since only assigned once
                            // Skip if already hoisted or declared (handles multiple with assertRaises as err)
                            if (!self.isDeclared(cm_var_name) and !self.hoisted_vars.contains(cm_var_name)) {
                                // Check for module-level function shadowing
                                const shadows_cm = self.module_level_funcs.contains(cm_var_name);
                                var actual_cm_name = cm_var_name;
                                if (shadows_cm and !self.var_renames.contains(cm_var_name)) {
                                    const prefixed_cm = try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ cm_var_name, self.lambda_counter });
                                    self.lambda_counter += 1;
                                    try self.var_renames.put(cm_var_name, prefixed_cm);
                                    actual_cm_name = prefixed_cm;
                                } else if (self.var_renames.get(cm_var_name)) |renamed_cm| {
                                    actual_cm_name = renamed_cm;
                                }
                                try self.emitIndent();
                                try self.emit("const ");
                                try self.emit(actual_cm_name);
                                try self.emit(": runtime.unittest.ContextManager = runtime.unittest.ContextManager{};\n");
                                try self.hoisted_vars.put(cm_var_name, {});
                            }
                        } else {
                            // Hoist regular context manager variable
                            try hoistVarWithExpr(self, cm_var_name, &cm_expr);
                        }
                    }
                }
            }
            // Also recursively hoist variables from nested with body
            try hoistWithBodyVars(self, stmt.with_stmt.body);
        } else if (stmt == .for_stmt) {
            // For loop inside with body - hoist the loop variable if iterating over tuple
            // Tuple iteration uses inline for, which requires the variable to be declared before the loop
            const for_s = stmt.for_stmt;
            const for_target_name: ?[]const u8 = if (for_s.target.* == .name) for_s.target.name.id else null;
            if (for_target_name) |var_name| {
                // Check if iterating over tuple literal (definitely needs hoisting)
                if (for_s.iter.* == .tuple) {
                    // Hoist tuple iteration variable - determine type from tuple elements
                    if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
                        try self.emitIndent();
                        try self.emit("var ");
                        try self.emit(var_name);
                        // Determine type from first tuple element
                        const tuple_elts = for_s.iter.tuple.elts;
                        if (tuple_elts.len > 0 and tuple_elts[0] == .constant) {
                            switch (tuple_elts[0].constant.value) {
                                .int => try self.emit(": i64 = undefined;\n"),
                                .float => try self.emit(": f64 = undefined;\n"),
                                .bool => try self.emit(": bool = undefined;\n"),
                                .string => try self.emit(": []const u8 = undefined;\n"),
                                else => try self.emit(": []const u8 = undefined;\n"),
                            }
                        } else {
                            // Default to []const u8 for non-constant tuples
                            try self.emit(": []const u8 = undefined;\n");
                        }
                        try self.hoisted_vars.put(var_name, {});
                    }
                }
            }
            // Recurse into for loop body, skipping assignments to the loop variable
            // e.g., `for line in file: line = line.strip()` - don't hoist line
            try hoistWithBodyVarsSkipping(self, for_s.body, for_target_name);
        } else if (stmt == .if_stmt) {
            // Recurse into if/else bodies (pass through skip_var)
            try hoistWithBodyVarsSkipping(self, stmt.if_stmt.body, skip_var);
            try hoistWithBodyVarsSkipping(self, stmt.if_stmt.else_body, skip_var);
        }
    }
}

/// Hoist a variable with @TypeOf(expr) for comptime type inference
fn hoistVarWithExpr(self: *NativeCodegen, var_name: []const u8, init_expr: *const ast.Node) CodegenError!void {
    // Skip hoisting function aliases - the assignment will be skipped too
    // e.g., `permutations = rpermutation` inside if block - rpermutation is a module-level function
    if (init_expr.* == .name) {
        if (self.module_level_funcs.contains(init_expr.name.id)) {
            return; // Don't hoist - functions are compile-time constants
        }
    }

    // Only hoist if not already declared in scope or previously hoisted
    if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
        // Check if var_name shadows a module-level function
        const shadows_module_func = self.module_level_funcs.contains(var_name);
        var actual_name = var_name;
        if (shadows_module_func and !self.var_renames.contains(var_name)) {
            const prefixed_name = try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ var_name, self.lambda_counter });
            self.lambda_counter += 1;
            try self.var_renames.put(var_name, prefixed_name);
            actual_name = prefixed_name;
        } else if (self.var_renames.get(var_name)) |renamed| {
            actual_name = renamed;
        }

        // Check for self-reference (e.g., `line = line.strip()`)
        // This would cause circular reference in @TypeOf - use fallback type instead
        const has_self_reference = var_hoisting.exprContainsName(init_expr, var_name);

        // Build safe vars from module-level functions (always available)
        var safe_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer safe_vars.deinit();
        var mod_iter = self.module_level_funcs.iterator();
        while (mod_iter.next()) |entry| {
            try safe_vars.put(entry.key_ptr.*, {});
        }

        try self.emitIndent();
        try self.emit("var ");
        try self.emit(actual_name);

        if (!has_self_reference and var_hoisting.initExprIsSafe(init_expr, &safe_vars)) {
            // Safe to use @TypeOf - no forward references and no self-references
            try self.emit(": @TypeOf(");
            try self.genExpr(init_expr.*);
            try self.emit(")");
        } else {
            // Has forward refs or self-reference - use fallback type
            const fallback = var_hoisting.inferFallbackType(init_expr, .for_loop);
            try self.emit(": ");
            try self.emit(fallback);
        }

        try self.emit(" = undefined;\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});
    }
}

/// Hoist a variable with @TypeOf(expr) using the exact name provided (for renamed vars)
/// Unlike hoistVarWithExpr, this skips isDeclared/hoisted checks (caller already verified)
fn hoistVarWithExprDirect(self: *NativeCodegen, actual_name: []const u8, init_expr: *const ast.Node) CodegenError!void {
    try self.emitIndent();
    try self.emit("var ");
    try self.emit(actual_name);
    try self.emit(": @TypeOf(");
    try self.genExpr(init_expr.*);
    try self.emit(") = undefined;\n");

    // Mark original name as hoisted (caller should handle the original->renamed mapping)
    try self.hoisted_vars.put(actual_name, {});
}

/// Generate with statement (context manager)
/// with open("file") as f: body => var f = ...; defer f.close(); body
/// In Python, 'f' is accessible after the with block, so we don't use nested blocks
pub fn genWith(self: *NativeCodegen, with_node: ast.Node.With) CodegenError!void {
    // Skip unittest context managers (assertWarns, assertRaises, etc.)
    // These are test helpers that don't have runtime implementations yet
    if (isUnittestContextManager(with_node.context_expr.*)) {
        // Since we're skipping this context manager call, we need to consume any
        // variables used in its arguments that aren't used elsewhere.
        // e.g., with self.assertRaisesRegex(TypeError, msg): -> _ = msg; (if msg not used in body)
        // e.g., with self.subTest(range=rng_name): -> _ = rng_name; (if rng_name not used in body)
        // Only discard if the variable is NOT used in the with body.
        if (with_node.context_expr.* == .call) {
            const call = with_node.context_expr.call;
            for (call.args) |arg| {
                // Emit discard for name references that aren't used in the body
                // Skip built-in exception/warning types (e.g., DeprecationWarning)
                if (arg == .name) {
                    const var_name = arg.name.id;
                    if (ExceptionTypes.has(var_name)) continue;
                    if (!varUsedInStatements(with_node.body, var_name)) {
                        try self.emitIndent();
                        try self.emit("_ = ");
                        try self.genExpr(arg);
                        try self.emit(";\n");
                    }
                }
            }
            // Also handle keyword arguments (e.g., subTest(range=rng_name))
            for (call.keyword_args) |kw| {
                if (kw.value == .name) {
                    const var_name = kw.value.name.id;
                    if (!varUsedInStatements(with_node.body, var_name)) {
                        try self.emitIndent();
                        try self.emit("_ = ");
                        try self.genExpr(kw.value);
                        try self.emit(";\n");
                    }
                }
            }
        }

        // If there's a target (as cm), declare it as a dummy value
        // Python code might use cm.exception.args[0] after the with block
        // Only handle simple name targets for unittest contexts (tuples not supported)
        if (with_node.optional_vars) |target| {
            if (target.* == .name) {
                const var_name = target.name.id;
                // Check if variable was hoisted or already declared (for multiple assertRaises in same scope)
                const is_hoisted = self.hoisted_vars.contains(var_name);
                const is_declared = self.isDeclared(var_name);
                const needs_decl = !is_hoisted and !is_declared;

                // Only emit declaration if variable not already declared
                // For repeated with statements using same variable, the const is already set
                if (needs_decl) {
                    try self.emitIndent();
                    // Use const for context manager variables (they're read-only)
                    try self.emit("const ");
                    try self.emit(var_name);
                    try self.emit(" = runtime.unittest.ContextManager{};\n");
                    // Always discard pointer to suppress unused warning
                    // Using pointer avoids "pointless discard" when variable IS used later
                    try self.emitIndent();
                    try self.emit("_ = &");
                    try self.emit(var_name);
                    try self.emit(";\n");
                    try self.declareVar(var_name);
                } else if (is_hoisted) {
                    // Variable was hoisted by scope analyzer - still need to assign value
                    try self.emitIndent();
                    try self.emit(var_name);
                    try self.emit(" = runtime.unittest.ContextManager{};\n");
                }
            }
        }

        // Handle tuple of context managers with named expressions
        // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
        if (with_node.context_expr.* == .tuple) {
            for (with_node.context_expr.tuple.elts) |elt| {
                if (elt == .named_expr) {
                    const named = elt.named_expr;
                    const var_name = named.target.name.id;
                    const cm_expr = named.value.*;

                    // Check if variable was hoisted or already declared
                    const is_hoisted = self.hoisted_vars.contains(var_name);
                    const is_declared = self.isDeclared(var_name);
                    const needs_decl = !is_hoisted and !is_declared;

                    // Check if this is a unittest context manager (assertRaises, etc.)
                    if (isUnittestContextManager(cm_expr)) {
                        // Emit dummy ContextManager for assertRaises/assertRaisesRegex
                        try self.emitIndent();
                        if (needs_decl) {
                            try self.emit("const ");
                        }
                        try self.emit(var_name);
                        try self.emit(" = runtime.unittest.ContextManager{};\n");
                        try self.emitIndent();
                        try self.emit("_ = &");
                        try self.emit(var_name);
                        try self.emit(";\n");
                    } else {
                        // Emit actual context manager (e.g., support.Stopwatch())
                        try self.emitIndent();
                        if (needs_decl) {
                            try self.emit("var ");
                        }
                        try self.emit(var_name);
                        try self.emit(" = ");
                        try self.genExpr(cm_expr);
                        try self.emit(";\n");
                        try self.emitIndent();
                        try self.emit("defer ");
                        try self.emit(var_name);
                        try self.emit(".close();\n");
                    }
                    if (needs_decl) {
                        try self.declareVar(var_name);
                    }
                }
            }
        }

        // For assertRaises/assertRaisesRegex, set context flag so builtins use catch instead of try
        // For assertWarns/assertLogs, just generate body normally
        const is_raises_context = isAssertRaisesContext(with_node.context_expr.*);

        if (is_raises_context) {
            const was_in_assert_raises = self.in_assert_raises_context;
            self.in_assert_raises_context = true;

            for (with_node.body) |stmt| {
                // For expression statements that might error, wrap the expression in catch
                // Use comptime check to handle both error unions and non-error types
                if (stmt == .expr_stmt) {
                    try self.emitIndent();
                    try self.emit("{ const __ar_expr = ");
                    try self.genExpr(stmt.expr_stmt.value.*);
                    try self.emit("; if (@typeInfo(@TypeOf(__ar_expr)) == .error_union) { _ = __ar_expr catch {}; } }\n");
                } else {
                    try self.generateStmt(stmt);
                }
            }

            // Restore context flag
            self.in_assert_raises_context = was_in_assert_raises;
        } else {
            // For assertWarns, assertLogs, subTest - just generate body normally
            for (with_node.body) |stmt| {
                try self.generateStmt(stmt);
            }
        }
        return;
    }

    // Track shadow rename info for restoration after body
    var with_shadow_original_name: ?[]const u8 = null;
    var with_shadow_old_rename: ?[]const u8 = null;
    var with_shadow_active: bool = false;

    // IMPORTANT: Set up shadow rename BEFORE hoisting when inside a nested function
    // This ensures the hoisted declaration uses the shadow name too
    if (with_node.optional_vars) |target| {
        if (target.* == .name) {
            const var_name = target.name.id;
            const is_declared = self.isDeclared(var_name);
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const needs_var = !is_declared and !is_hoisted;

            // Set up shadow rename FIRST if inside nested function
            if (self.inside_nested_function and needs_var) {
                const shadow_rename = try std.fmt.allocPrint(self.allocator, "__with_{s}_{d}", .{ var_name, self.lambda_counter });
                self.lambda_counter += 1;
                with_shadow_original_name = var_name;
                with_shadow_old_rename = self.var_renames.get(var_name);
                with_shadow_active = true;
                try self.var_renames.put(var_name, shadow_rename);
            }

            // Now hoist with the (possibly renamed) variable
            // Pass the renamed name if we set one up, so hoistVarWithExpr can check correctly
            if (needs_var) {
                const hoist_name = self.var_renames.get(var_name) orelse var_name;
                try hoistVarWithExprDirect(self, hoist_name, with_node.context_expr);
            }
        }
    }

    // Python semantics: variables assigned inside with blocks are accessible after the block ends
    // We MUST hoist these variables BEFORE opening the block scope
    try hoistWithBodyVars(self, with_node.body);

    // If there's a target (as f) or (as (a, b)), declare it at current scope
    if (with_node.optional_vars) |target| {
        // Infer the type of the context expression
        const context_type = try self.type_inferrer.inferExpr(with_node.context_expr.*);

        if (target.* == .name) {
            // Simple name target: `with ctx() as f:`
            const original_name = target.name.id;
            // Use renamed name if we set up a shadow rename earlier
            const var_name = self.var_renames.get(original_name) orelse original_name;

            try self.type_inferrer.var_types.put(var_name, context_type);

            // NOTE: with-target variable was already hoisted BEFORE hoistWithBodyVars
            // (at the start of genWith) to ensure body variables can reference it

            // Open a block for defer scope - the defer will close the file at end of body
            try self.emitIndent();
            try self.emit("{\n");
            self.indent();

            // For file types, assign directly and defer close
            // For other context managers, call __enter__() and defer __exit__()
            try self.emitIndent();
            if (context_type == .file) {
                // File context manager - assign directly, it returns self from __enter__
                try self.emit(var_name);
                try self.emit(" = ");
                try self.genExpr(with_node.context_expr.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.emit("defer runtime.PyFile.close(");
                try self.emit(var_name);
                try self.emit(");\n");
            } else {
                // General context manager - store CM, call __enter__(), defer __exit__()
                // Use var since __enter__/__exit__ may take *@This() (mutable self)
                // Use unique name for nested with statements
                const cm_id = self.lambda_counter;
                self.lambda_counter += 1;
                try self.output.writer(self.allocator).print("var __with_cm_{d} = ", .{cm_id});
                try self.genExpr(with_node.context_expr.*);
                try self.emit(";\n");
                // Defer __exit__ before calling __enter__ (Python semantics)
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {{ _ = __with_cm_{d}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_id});
                // Call __enter__() and assign result to target variable
                try self.emitIndent();
                try self.emit(var_name);
                try self.output.writer(self.allocator).print(" = try __with_cm_{d}.__enter__(__global_allocator);\n", .{cm_id});
            }
        } else if (target.* == .tuple or target.* == .list) {
            // Tuple/list unpacking target: `with ctx() as (a, b):`
            // Python semantics: (a, b) = context_manager.__enter__()
            const elts = if (target.* == .tuple) target.tuple.elts else target.list.elts;

            // Open a block for defer scope first
            try self.emitIndent();
            try self.emit("{\n");
            self.indent();

            // Store the context manager itself (for cleanup)
            // Use var since __enter__/__exit__ may take *@This() (mutable self)
            // Use unique name for nested with statements
            const cm_id = self.lambda_counter;
            self.lambda_counter += 1;
            try self.emitIndent();
            if (context_type == .file) {
                try self.output.writer(self.allocator).print("const __with_cm_{d} = ", .{cm_id});
            } else {
                try self.output.writer(self.allocator).print("var __with_cm_{d} = ", .{cm_id});
            }
            try self.genExpr(with_node.context_expr.*);
            try self.emit(";\n");

            // Add defer for cleanup (calls __exit__ / close on the context manager)
            try self.emitIndent();
            if (context_type == .file) {
                try self.output.writer(self.allocator).print("defer runtime.PyFile.close(__with_cm_{d});\n", .{cm_id});
            } else {
                try self.output.writer(self.allocator).print("defer {{ _ = __with_cm_{d}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_id});
            }

            // Call __enter__() to get the value to unpack
            // For most context managers, __enter__() returns a tuple/value
            try self.emitIndent();
            if (context_type == .file) {
                try self.output.writer(self.allocator).print("const __with_val_{d} = __with_cm_{d};\n", .{ cm_id, cm_id });
            } else {
                try self.output.writer(self.allocator).print("const __with_val_{d} = try __with_cm_{d}.__enter__(__global_allocator);\n", .{ cm_id, cm_id });
            }

            // Unpack tuple elements from __enter__()'s return value
            for (elts, 0..) |elt, i| {
                if (elt == .name) {
                    const elt_name = elt.name.id;
                    const is_declared = self.isDeclared(elt_name);
                    const is_hoisted = self.hoisted_vars.contains(elt_name);

                    try self.emitIndent();
                    if (!is_declared and !is_hoisted) {
                        try self.emit("const ");
                    }
                    try self.emit(elt_name);
                    try self.output.writer(self.allocator).print(" = __with_val_{d}[{d}];\n", .{ cm_id, i });

                    if (!is_declared and !is_hoisted) {
                        try self.declareVar(elt_name);
                    }
                }
            }
        } else {
            // Unsupported target type - just open block and generate context
            // Use unique name for nested with statements
            const cm_id = self.lambda_counter;
            self.lambda_counter += 1;
            try self.emitIndent();
            try self.emit("{\n");
            self.indent();
            try self.emitIndent();
            if (context_type == .file) {
                try self.output.writer(self.allocator).print("const __with_ctx_{d} = ", .{cm_id});
            } else {
                try self.output.writer(self.allocator).print("var __with_ctx_{d} = ", .{cm_id});
            }
            try self.genExpr(with_node.context_expr.*);
            try self.emit(";\n");
            try self.emitIndent();
            if (context_type == .file) {
                try self.output.writer(self.allocator).print("defer runtime.PyFile.close(__with_ctx_{d});\n", .{cm_id});
            } else {
                try self.output.writer(self.allocator).print("defer {{ _ = __with_ctx_{d}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_id});
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = try __with_ctx_{d}.__enter__(__global_allocator);\n", .{cm_id});
            }
        }
    } else {
        // No variable - just execute context expression and defer cleanup
        // First, hoist any variables declared in body (similar to try-except)
        // This is needed because Python allows variables defined inside with blocks
        // to be used after the block ends
        try hoistWithBodyVars(self, with_node.body);

        // Infer type for cleanup strategy
        const context_type = try self.type_inferrer.inferExpr(with_node.context_expr.*);

        // Use unique name for nested with statements
        const cm_id = self.lambda_counter;
        self.lambda_counter += 1;
        try self.emitIndent();
        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        if (context_type == .file) {
            try self.output.writer(self.allocator).print("const __ctx_{d} = ", .{cm_id});
        } else {
            try self.output.writer(self.allocator).print("var __ctx_{d} = ", .{cm_id});
        }
        try self.genExpr(with_node.context_expr.*);
        try self.emit(";\n");
        try self.emitIndent();
        if (context_type == .file) {
            try self.output.writer(self.allocator).print("defer runtime.PyFile.close(__ctx_{d});\n", .{cm_id});
        } else {
            try self.output.writer(self.allocator).print("defer {{ _ = __ctx_{d}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_id});
            try self.emitIndent();
            try self.output.writer(self.allocator).print("_ = try __ctx_{d}.__enter__(__global_allocator);\n", .{cm_id});
        }
    }

    // Generate body
    // If we're inside an assertRaises context (from a parent with statement),
    // wrap expression statements in error-catching code
    for (with_node.body) |stmt| {
        if (self.in_assert_raises_context and stmt == .expr_stmt) {
            // Wrap expression in error catch for assertRaises context
            try self.emitIndent();
            try self.emit("{ const __ar_expr = ");
            try self.genExpr(stmt.expr_stmt.value.*);
            try self.emit("; if (@typeInfo(@TypeOf(__ar_expr)) == .error_union) { _ = __ar_expr catch {}; } }\n");
        } else {
            try self.generateStmt(stmt);
        }
    }

    // Restore var_renames after with body if we added a shadow rename
    // This ensures the rename only applies within the with block body
    if (with_shadow_active) {
        if (with_shadow_old_rename) |old| {
            try self.var_renames.put(with_shadow_original_name.?, old);
        } else {
            _ = self.var_renames.swapRemove(with_shadow_original_name.?);
        }
    }

    // Close block for both cases - with variable and without
    // When there's a variable, we opened a block for defer scope
    // When there's no variable, we also opened a block
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Extract exception type name from an expression
/// Handles both direct name (ValueError) and call (ValueError("msg"))
fn getExceptionName(exc: *const ast.Node) []const u8 {
    switch (exc.*) {
        .call => |call| {
            if (call.func.* == .name) {
                return call.func.name.id;
            }
            return "Exception";
        },
        .name => |n| return n.id,
        else => return "Exception",
    }
}

/// Generate raise statement
/// raise ValueError("msg") => return error.ValueError
/// raise => return error.Exception
/// NOTE: We use Zig errors so try/except can catch them.
/// When debug info is available, prints Python-style error message before returning.
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    // Record line mapping for debug info (maps Python raise line -> Zig line)
    self.recordRaiseLineMapping();

    // Inside finally block: break out of the labeled block with the error
    // This allows the exception to be captured and propagated after finally completes
    if (self.inside_finally_block) {
        if (raise_node.exc) |exc| {
            // Extract exception type name from the raise expression
            const exc_name = getExceptionName(exc);
            // Print Python-style error message if we have one
            if (exc.* == .call) {
                const call = exc.call;
                if (call.args.len > 0) {
                    try self.emitIndent();
                    try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                    try self.emit(exc_name);
                    try self.emit("\", ");
                    try genRaiseMessage(self, call.args[0]);
                    try self.emit(", @src().line);\n");
                }
            }
            // Break out of finally block with the error
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :__finally_blk_{d} error.{s};\n", .{ self.current_finally_id, exc_name });
        } else {
            // Bare raise - re-raise the current exception (use generic error)
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :__finally_blk_{d} error.Exception;\n", .{self.current_finally_id});
        }
        self.control_flow_terminated = true;
        return;
    }

    // Inside defer but not finally block (legacy path) - skip raise
    if (self.inside_defer) {
        try self.emitIndent();
        try self.emit("// raise inside defer - cannot propagate\n");
        return;
    }

    if (raise_node.exc) |exc| {
        // Check if this is an exception constructor call: raise ValueError("msg")
        if (exc.* == .call) {
            const call = exc.call;
            if (call.func.* == .name) {
                const exc_name = call.func.name.id;
                // Check if it's a known exception type
                if (ExceptionTypes.has(exc_name)) {
                    // Print Python-style error message if we have a message argument
                    if (call.args.len > 0) {
                        try self.emitIndent();
                        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                        try self.emit(exc_name);
                        try self.emit("\", ");
                        // Generate the message argument
                        try genRaiseMessage(self, call.args[0]);
                        try self.emit(", @src().line);\n");
                    }
                    // Generate: return error.ValueError
                    try self.emitIndent();
                    try self.emit("return error.");
                    try self.emit(exc_name);
                    try self.emit(";\n");
                    self.control_flow_terminated = true;
                    return;
                }
            }
        }
        // Check if this is just an exception name: raise TypeError
        if (exc.* == .name) {
            const exc_name = exc.name.id;
            if (ExceptionTypes.has(exc_name)) {
                // Print Python-style error without message
                try self.emitIndent();
                try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"");
                try self.emit(exc_name);
                try self.emit("\", \"\", @src().line);\n");
                // Generate: return error.TypeError
                try self.emitIndent();
                try self.emit("return error.");
                try self.emit(exc_name);
                try self.emit(";\n");
                self.control_flow_terminated = true;
                return;
            }
        }
        // Fallback for other raise expressions - use generic error
        try self.emitIndent();
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"Exception\", \"\", @src().line);\n");
        try self.emitIndent();
        try self.emit("return error.Exception;\n");
    } else {
        // bare raise - use generic error
        try self.emitIndent();
        try self.emit("runtime.debug_reader.printPythonError(__global_allocator, \"Exception\", \"\", @src().line);\n");
        try self.emitIndent();
        try self.emit("return error.Exception;\n");
    }
    self.control_flow_terminated = true;
}

/// Generate the error message for a raise statement
/// Handles string literals and expressions
fn genRaiseMessage(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const expressions = @import("../expressions.zig");
    if (arg == .constant and arg.constant.value == .string) {
        // String literal - emit directly
        try self.emit("\"");
        try self.emit(arg.constant.value.string);
        try self.emit("\"");
    } else {
        // Expression - convert to string at runtime
        try self.emit("(try runtime.builtins.pyStr(__global_allocator, ");
        try expressions.genExpr(self, arg);
        try self.emit("))");
    }
}

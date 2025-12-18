/// With statement code generation (context managers)
const std = @import("std");
const ast = @import("analysis.ast");
const zig_keywords = @import("utils.zig_keywords");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const shared = @import("../../shared_maps.zig");
const ExceptionTypes = shared.RuntimeExceptions;
const var_hoisting = @import("../functions/var_hoisting.zig");
const hashmap_helper = @import("utils.hashmap_helper");

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
        .listcomp => |l| blk: {
            if (exprUsesVar(l.elt.*, var_name)) break :blk true;
            for (l.generators) |gen| {
                if (exprUsesVar(gen.iter.*, var_name)) break :blk true;
                for (gen.ifs) |cond| {
                    if (exprUsesVar(cond, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .dictcomp => |d| blk: {
            if (exprUsesVar(d.key.*, var_name) or exprUsesVar(d.value.*, var_name)) break :blk true;
            for (d.generators) |gen| {
                if (exprUsesVar(gen.iter.*, var_name)) break :blk true;
                for (gen.ifs) |cond| {
                    if (exprUsesVar(cond, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .genexp => |g| blk: {
            if (exprUsesVar(g.elt.*, var_name)) break :blk true;
            for (g.generators) |gen| {
                if (exprUsesVar(gen.iter.*, var_name)) break :blk true;
                for (gen.ifs) |cond| {
                    if (exprUsesVar(cond, var_name)) break :blk true;
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
        .ann_assign => |a| blk: {
            if (exprUsesVar(a.target.*, var_name)) break :blk true;
            if (a.value) |v| if (exprUsesVar(v.*, var_name)) break :blk true;
            break :blk false;
        },
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
            if (f.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (exprUsesVar(w.condition.*, var_name)) break :blk true;
            for (w.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            if (w.orelse_body) |orelse_body| {
                for (orelse_body) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
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
            for (t.else_body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            if (exprUsesVar(m.subject.*, var_name)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |g| if (exprUsesVar(g.*, var_name)) break :blk true;
                for (case.body) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .assert_stmt => |a| blk: {
            if (exprUsesVar(a.condition.*, var_name)) break :blk true;
            if (a.msg) |m| if (exprUsesVar(m.*, var_name)) break :blk true;
            break :blk false;
        },
        .raise_stmt => |r| blk: {
            if (r.exc) |e| if (exprUsesVar(e.*, var_name)) break :blk true;
            if (r.cause) |c| if (exprUsesVar(c.*, var_name)) break :blk true;
            break :blk false;
        },
        .yield_stmt => |y| if (y.value) |v| exprUsesVar(v.*, var_name) else false,
        .yield_from_stmt => |y| exprUsesVar(y.value.*, var_name),
        .function_def => |f| blk: {
            for (f.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .class_def => |c| blk: {
            for (c.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
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

/// Recursively check if a list of statements contains a raise_stmt or expr_stmt
/// This is needed because assertRaises blocks need labeled blocks when they contain
/// statements that might raise, even if those are nested inside other blocks (if, with, for, etc.)
fn containsRaiseOrExprStmt(stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .raise_stmt => return true,
            .expr_stmt => return true,
            // Recurse into compound statements
            .if_stmt => |if_node| {
                if (containsRaiseOrExprStmt(if_node.body)) return true;
                if (if_node.else_body.len > 0) {
                    if (containsRaiseOrExprStmt(if_node.else_body)) return true;
                }
            },
            .for_stmt => |for_node| {
                if (containsRaiseOrExprStmt(for_node.body)) return true;
                if (for_node.orelse_body) |orelse_body| {
                    if (containsRaiseOrExprStmt(orelse_body)) return true;
                }
            },
            .while_stmt => |while_node| {
                if (containsRaiseOrExprStmt(while_node.body)) return true;
                if (while_node.orelse_body) |orelse_body| {
                    if (containsRaiseOrExprStmt(orelse_body)) return true;
                }
            },
            .with_stmt => |with_node| {
                if (containsRaiseOrExprStmt(with_node.body)) return true;
            },
            .try_stmt => |try_node| {
                if (containsRaiseOrExprStmt(try_node.body)) return true;
                for (try_node.handlers) |handler| {
                    if (containsRaiseOrExprStmt(handler.body)) return true;
                }
                if (try_node.else_body.len > 0) {
                    if (containsRaiseOrExprStmt(try_node.else_body)) return true;
                }
                if (try_node.finalbody.len > 0) {
                    if (containsRaiseOrExprStmt(try_node.finalbody)) return true;
                }
            },
            .match_stmt => |match_node| {
                for (match_node.cases) |case| {
                    if (containsRaiseOrExprStmt(case.body)) return true;
                }
            },
            else => {},
        }
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
                // Check for contextlib.* context managers (redirect_stdout, redirect_stderr, suppress, etc.)
                // Check for mock.patch* context managers
                if (std.mem.eql(u8, obj_name, "contextlib") or std.mem.eql(u8, obj_name, "mock")) {
                    return true;
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
    try hoistWithBodyVarsSkipping(self, body, null);
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
                                const prefixed_name = try self.name_gen.local(var_name);
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
                                    const prefixed_cm = try self.name_gen.local(cm_var_name);
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
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
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
            const prefixed_name = try self.name_gen.local(var_name);
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
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);

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
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
    try self.emit(": @TypeOf(");
    try self.genExpr(init_expr.*);
    try self.emit(") = undefined;\n");

    // Mark original name as hoisted (caller should handle the original->renamed mapping)
    try self.hoisted_vars.put(actual_name, {});
}

/// Check if an expression is an assertion call (self.assert*)
/// These calls generate complete statements, not expressions, so they
/// should not be wrapped in `const __ar_expr = ...` in assertRaises context.
fn isAssertionCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;
    // Check for self.assert* pattern (attribute access on self)
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        // Check if the attribute name starts with "assert"
        if (attr.attr.len >= 6 and std.mem.startsWith(u8, attr.attr, "assert")) {
            return true;
        }
    }
    return false;
}

/// Generate with statement (context manager)
/// with open("file") as f: body => var f = ...; defer f.close(); body
/// In Python, 'f' is accessible after the with block, so we don't use nested blocks
pub fn genWith(self: *NativeCodegen, with_node: ast.Node.With) CodegenError!void {
    const b = try self.getBuilder();
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
                        const arg_val = try self.captureExpr(arg);
                        try b.writeIndent();
                        // Use _ = &var to avoid "pointless discard of local constant" error
                        try b.write("_ = &");
                        try b.emitValue(arg_val, .{});
                        try b.write(";\n");
                    }
                }
            }
            // Also handle keyword arguments (e.g., subTest(range=rng_name))
            for (call.keyword_args) |kw| {
                if (kw.value == .name) {
                    const var_name = kw.value.name.id;
                    if (!varUsedInStatements(with_node.body, var_name)) {
                        const kw_val = try self.captureExpr(kw.value);
                        try b.writeIndent();
                        // Use _ = &var to avoid "pointless discard of local constant" error
                        try b.write("_ = &");
                        try b.emitValue(kw_val, .{});
                        try b.write(";\n");
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
                    try b.writeIndent();
                    // Use const for context manager variables (they're read-only)
                    try b.write("const ");
                    try b.write(var_name);
                    try b.write(" = runtime.unittest.ContextManager{};\n");
                    // Always discard pointer to suppress unused warning
                    // Using pointer avoids "pointless discard" when variable IS used later
                    try b.writeIndent();
                    try b.write("_ = &");
                    try b.write(var_name);
                    try b.write(";\n");
                    try self.declareVar(var_name);
                } else if (is_hoisted) {
                    // Variable was hoisted by scope analyzer - still need to assign value
                    try b.writeIndent();
                    try b.write(var_name);
                    try b.write(" = runtime.unittest.ContextManager{};\n");
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
                        try b.writeIndent();
                        if (needs_decl) {
                            try b.write("const ");
                        }
                        // Capture escaped identifier
                        const start_pos = self.output.items.len;
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                        const escaped_var = self.output.items[start_pos..];
                        const escaped_copy = try self.arena.allocator().dupe(u8, escaped_var);
                        self.output.shrinkRetainingCapacity(start_pos);
                        try b.write(escaped_copy);
                        try b.write(" = runtime.unittest.ContextManager{};\n");
                        try b.writeIndent();
                        try b.write("_ = &");
                        try b.write(escaped_copy);
                        try b.write(";\n");
                    } else {
                        // Emit actual context manager (e.g., support.Stopwatch())
                        try b.writeIndent();
                        if (needs_decl) {
                            try b.write("var ");
                        }
                        // Capture escaped identifier
                        const start_pos = self.output.items.len;
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                        const escaped_var = self.output.items[start_pos..];
                        const escaped_copy = try self.arena.allocator().dupe(u8, escaped_var);
                        self.output.shrinkRetainingCapacity(start_pos);
                        try b.write(escaped_copy);
                        try b.write(" = ");
                        const cm_val = try self.captureExpr(cm_expr);
                        try b.emitValue(cm_val, .{});
                        try b.write(";\n");
                        try b.writeIndent();
                        try b.write("defer ");
                        try b.write(escaped_copy);
                        try b.write(".close();\n");
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

            // Set inside_try_body so that any error-returning calls propagate errors
            // instead of using catch unreachable
            const prev_inside_try = self.inside_try_body;
            self.inside_try_body = true;

            // Check recursively if body contains raise or expr statements
            // Must be recursive because the statement might be nested inside other blocks (if, with, for, etc.)
            const needs_labeled_block = containsRaiseOrExprStmt(with_node.body);

            // Generate a labeled block only if we have expression statements that might error
            const block_id = self.assert_raises_block_id;
            self.assert_raises_block_id += 1;
            // Track current block ID for genRaise to use when breaking out
            const saved_assert_raises_block_id = self.current_assert_raises_block_id;
            self.current_assert_raises_block_id = block_id;

            if (needs_labeled_block) {
                try b.writeIndent();
                try b.writeFmt("_ = __ar_blk_{d}: {{\n", .{block_id});
                self.indent();
            }

            // Flush builder output before generating body statements
            // Body generation uses self.generateStmt/genExpr which write to self.output
            {
                const body_prefix = b.getBody();
                try self.output.appendSlice(self.allocator, body_prefix);
                b.body.clearRetainingCapacity();
            }

            // Save and reset control_flow_terminated for the block body
            const saved_control_flow = self.control_flow_terminated;
            self.control_flow_terminated = false;

            // Generate body statements - for expression statements, catch any errors
            for (with_node.body) |stmt| {
                // Skip if control flow already terminated (e.g., after raise)
                if (self.control_flow_terminated) break;

                // For expression statements, wrap to catch errors
                // The expression is assigned to __ar_val, then if it's an error union or error set, catch it
                if (stmt == .expr_stmt) {
                    try self.emitIndent();
                    try self.emit("{\n");
                    self.indent();
                    try self.emitIndent();
                    try self.emit("const __ar_val = ");
                    const before_expr = self.output.items.len;
                    try self.genExpr(stmt.expr_stmt.value.*);
                    // Check if the generated expression already ends with semicolon (e.g., if statements)
                    // If so, don't add another semicolon
                    const generated = self.output.items[before_expr..];
                    if (generated.len == 0 or generated[generated.len - 1] != ';') {
                        try self.emit(";\n");
                    } else {
                        try self.emit("\n");
                    }
                    try self.emitIndent();
                    // Use unittest.expectError() which handles both error and non-error types
                    // internally via @typeInfo branching (avoids Zig type-checking unreachable branches)
                    try self.emitFmt("if (!unittest.expectError(__ar_val)) break :__ar_blk_{d} {{}};\n", .{block_id});
                    self.dedent();
                    try self.emitIndent();
                    try self.emit("}\n");
                } else {
                    try self.generateStmt(stmt);
                }
            }

            // Close block and handle test pass/fail
            if (needs_labeled_block) {
                // If body completed normally without raising, test fails
                if (!self.control_flow_terminated) {
                    try self.emitIndent();
                    try self.emit("return error.ExpectedExceptionNotRaised;\n");
                }
                self.dedent();
                try self.emitIndent();
                try self.emit("};\n");
            } else {
                // No expression/raise statements - body has non-error statements
                // This is a test case that expects error from non-expr stmt (if condition, etc)
                // For now, just generate the body and mark as TODO
                // The comparison/condition should return error which propagates up
            }

            // Restore flags
            self.control_flow_terminated = saved_control_flow;
            self.inside_try_body = prev_inside_try;
            self.current_assert_raises_block_id = saved_assert_raises_block_id;

            // Restore context flag
            self.in_assert_raises_context = was_in_assert_raises;
        } else {
            // For assertWarns, assertLogs, subTest - just generate body normally
            for (with_node.body) |stmt| {
                try self.generateStmt(stmt);
            }
        }

        // Flush builder output before early return
        const builder_output = b.getBody();
        try self.output.appendSlice(self.allocator, builder_output);
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
                const shadow_rename = try b.freshName(try std.fmt.allocPrint(self.allocator, "with_{s}", .{var_name}));
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

            // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
            try self.type_inferrer.putScopedVar(var_name, context_type);

            // NOTE: with-target variable was already hoisted BEFORE hoistWithBodyVars
            // (at the start of genWith) to ensure body variables can reference it

            // Open a block for defer scope - the defer will close the file at end of body
            try b.writeIndent();
            try b.write("{\n");
            self.indent();

            // Capture the context manager expression
            const ctx_expr_val = try self.captureExpr(with_node.context_expr.*);

            // For file types, assign directly and defer close
            // For other context managers, call __enter__() and defer __exit__()
            try b.writeIndent();
            if (context_type == .file) {
                // File context manager - assign directly, it returns self from __enter__
                try b.write(var_name);
                try b.write(" = ");
                try b.emitValue(ctx_expr_val, .{});
                try b.write(";\n");
                try b.writeIndent();
                try b.write("defer runtime.PyFile.close(");
                try b.write(var_name);
                try b.write(");\n");
            } else {
                // General context manager - store CM, call __enter__(), defer __exit__()
                // Use var since __enter__/__exit__ may take *@This() (mutable self)
                // Use unique name for nested with statements
                const cm_name = try b.freshName("with_cm");
                try b.writeFmt("var {s} = ", .{cm_name});
                try b.emitValue(ctx_expr_val, .{});
                try b.write(";\n");
                // Defer __exit__ before calling __enter__ (Python semantics)
                try b.writeIndent();
                try b.writeFmt("defer {{ _ = {s}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_name});
                // Call __enter__() and assign result to target variable
                try b.writeIndent();
                try b.write(var_name);
                try b.writeFmt(" = try {s}.__enter__(__global_allocator);\n", .{cm_name});
            }
        } else if (target.* == .tuple or target.* == .list) {
            // Tuple/list unpacking target: `with ctx() as (a, b):`
            // Python semantics: (a, b) = context_manager.__enter__()
            const elts = if (target.* == .tuple) target.tuple.elts else target.list.elts;

            // Open a block for defer scope first
            try b.writeIndent();
            try b.write("{\n");
            self.indent();

            // Store the context manager itself (for cleanup)
            // Use var since __enter__/__exit__ may take *@This() (mutable self)
            // Use unique name for nested with statements
            const cm_name = try b.freshName("with_cm");
            const val_name = try b.freshName("with_val");
            const ctx_expr_tuple = try self.captureExpr(with_node.context_expr.*);

            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("const {s} = ", .{cm_name});
            } else {
                try b.writeFmt("var {s} = ", .{cm_name});
            }
            try b.emitValue(ctx_expr_tuple, .{});
            try b.write(";\n");

            // Add defer for cleanup (calls __exit__ / close on the context manager)
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("defer runtime.PyFile.close({s});\n", .{cm_name});
            } else {
                try b.writeFmt("defer {{ _ = {s}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{cm_name});
            }

            // Call __enter__() to get the value to unpack
            // For most context managers, __enter__() returns a tuple/value
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("const {s} = {s};\n", .{ val_name, cm_name });
            } else {
                try b.writeFmt("const {s} = try {s}.__enter__(__global_allocator);\n", .{ val_name, cm_name });
            }

            // Unpack tuple elements from __enter__()'s return value
            for (elts, 0..) |elt, i| {
                if (elt == .name) {
                    const elt_name = elt.name.id;
                    const is_declared = self.isDeclared(elt_name);
                    const is_hoisted = self.hoisted_vars.contains(elt_name);

                    try b.writeIndent();
                    if (!is_declared and !is_hoisted) {
                        try b.write("const ");
                    }
                    try b.write(elt_name);
                    try b.writeFmt(" = {s}[{d}];\n", .{ val_name, i });

                    if (!is_declared and !is_hoisted) {
                        try self.declareVar(elt_name);
                    }
                }
            }
        } else {
            // Unsupported target type - just open block and generate context
            // Use unique name for nested with statements
            const ctx_name = try b.freshName("with_ctx");
            const ctx_expr_other = try self.captureExpr(with_node.context_expr.*);

            try b.writeIndent();
            try b.write("{\n");
            self.indent();
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("const {s} = ", .{ctx_name});
            } else {
                try b.writeFmt("var {s} = ", .{ctx_name});
            }
            try b.emitValue(ctx_expr_other, .{});
            try b.write(";\n");
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("defer runtime.PyFile.close({s});\n", .{ctx_name});
            } else {
                try b.writeFmt("defer {{ _ = {s}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{ctx_name});
                try b.writeIndent();
                try b.writeFmt("_ = try {s}.__enter__(__global_allocator);\n", .{ctx_name});
            }
        }
    } else {
        // No variable - just execute context expression and defer cleanup
        // First, hoist any variables declared in body (similar to try-except)
        // This is needed because Python allows variables defined inside with blocks
        // to be used after the block ends
        try hoistWithBodyVars(self, with_node.body);

        // Open a block for defer scope
        try b.writeIndent();
        try b.write("{\n");
        self.indent();

        // Check if context_expr is a tuple of context managers (Python 3.10+ syntax)
        // e.g., with (cm1(), cm2()): body
        if (with_node.context_expr.* == .tuple) {
            const tuple_elts = with_node.context_expr.tuple.elts;

            // Handle each context manager in the tuple
            for (tuple_elts) |cm_expr| {
                // Skip unittest context managers (they're no-ops)
                if (isUnittestContextManager(cm_expr)) {
                    continue;
                }

                // Extract actual expression from named_expr if present
                const actual_cm_expr = if (cm_expr == .named_expr) cm_expr.named_expr.value.* else cm_expr;

                // Infer type for cleanup strategy
                const cm_type = try self.type_inferrer.inferExpr(actual_cm_expr);

                // Capture the context manager expression
                const cm_val = try self.captureExpr(actual_cm_expr);

                // Generate unique name for this context manager
                const ctx_name = try b.freshName("ctx");
                try b.writeIndent();
                if (cm_type == .file) {
                    try b.writeFmt("const {s} = ", .{ctx_name});
                } else {
                    try b.writeFmt("var {s} = ", .{ctx_name});
                }
                try b.emitValue(cm_val, .{});
                try b.write(";\n");

                // Emit defer for cleanup
                try b.writeIndent();
                if (cm_type == .file) {
                    try b.writeFmt("defer runtime.PyFile.close({s});\n", .{ctx_name});
                } else {
                    try b.writeFmt("defer {{ _ = {s}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{ctx_name});
                    try b.writeIndent();
                    try b.writeFmt("_ = try {s}.__enter__(__global_allocator);\n", .{ctx_name});
                }
            }
        } else {
            // Single context manager (original behavior)
            // Infer type for cleanup strategy
            const context_type = try self.type_inferrer.inferExpr(with_node.context_expr.*);

            // Capture the context manager expression
            const ctx_val = try self.captureExpr(with_node.context_expr.*);

            // Use unique name for nested with statements
            const ctx_name = try b.freshName("ctx");
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("const {s} = ", .{ctx_name});
            } else {
                try b.writeFmt("var {s} = ", .{ctx_name});
            }
            try b.emitValue(ctx_val, .{});
            try b.write(";\n");
            try b.writeIndent();
            if (context_type == .file) {
                try b.writeFmt("defer runtime.PyFile.close({s});\n", .{ctx_name});
            } else {
                try b.writeFmt("defer {{ _ = {s}.__exit__(__global_allocator, null, null, null) catch {{}}; }}\n", .{ctx_name});
                try b.writeIndent();
                try b.writeFmt("_ = try {s}.__enter__(__global_allocator);\n", .{ctx_name});
            }
        }
    }

    // Flush builder output to self.output BEFORE generating body
    // This ensures context manager setup is emitted before body statements
    const builder_output = b.getBody();
    try self.output.appendSlice(self.allocator, builder_output);

    // Generate body
    // If we're inside an assertRaises context (from a parent with statement),
    // wrap expression statements in error-catching code
    // EXCEPTION: Assertion calls (self.assert*) generate complete statements, not expressions
    for (with_node.body) |stmt| {
        if (self.in_assert_raises_context and stmt == .expr_stmt) {
            // Check if this is an assertion call (generates statement, not expression)
            const is_assertion = isAssertionCall(stmt.expr_stmt.value.*);
            if (is_assertion) {
                // Don't wrap - assertions generate complete statements like:
                // if (!...) return error.AssertionFailed;
                // Wrapping would cause double-semicolon syntax error
                try self.generateStmt(stmt);
            } else {
                // Wrap non-assertion expressions for error catching
                try self.emitIndent();
                try self.emit("{ const __ar_expr = ");
                try self.genExpr(stmt.expr_stmt.value.*);
                try self.emit("; if (@typeInfo(@TypeOf(__ar_expr)) == .error_union) { _ = __ar_expr catch {}; } }\n");
            }
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

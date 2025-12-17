/// For loop code generation (basic, range, tuple unpacking)
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const for_special = @import("for_special.zig");
const genEnumerateLoop = for_special.genEnumerateLoop;
const genZipLoop = for_special.genZipLoop;
const zig_keywords = @import("utils.zig_keywords");
const producesBlockExpression = @import("../../../expressions.zig").producesBlockExpression;
const triggerDeferredClosureInstantiations = @import("../../assign.zig").triggerDeferredClosureInstantiations;
const string_traits = @import("../../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../../../expr_emitter.zig");

/// Check if an expression is a lazy class attribute access (self.ATTR where ATTR is lazy)
/// Returns the attribute name if it is, null otherwise
fn isLazyClassAttrAccess(self: *NativeCodegen, expr: ast.Node) ?[]const u8 {
    // Check if it's an attribute access on 'self'
    if (expr != .attribute) return null;
    const attr = expr.attribute;

    // Must be accessing self
    if (attr.value.* != .name) return null;
    if (!std.mem.eql(u8, attr.value.name.id, "self")) return null;

    // Check if we're in a class and this attribute is registered as lazy
    const class_name = self.current_class_name orelse return null;
    var lazy_key_buf: [256]u8 = undefined;
    const lazy_key = std.fmt.bufPrint(&lazy_key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch return null;

    // Check if it's in class_type_attrs with "__lazy__" value
    if (self.class_type_attrs.get(lazy_key)) |attr_type| {
        if (std.mem.eql(u8, attr_type, "__lazy__")) {
            return attr.attr;
        }
    }
    return null;
}

/// Sanitize Python variable name for Zig (e.g., "_" -> "_unused")
fn sanitizeVarName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "_")) return "_unused";
    return name;
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
        .set => |s| blk: {
            for (s.elts) |e| {
                if (exprUsesVar(e, var_name)) break :blk true;
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
        .named_expr => |n| exprUsesVar(n.value.*, var_name),
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
            if (a.value) |v| {
                if (exprUsesVar(v.*, var_name)) break :blk true;
            }
            break :blk exprUsesVar(a.target.*, var_name);
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
            if (f.orelse_body) |ob| {
                for (ob) |s| {
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
            if (w.orelse_body) |ob| {
                for (ob) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .return_stmt => |r| if (r.value) |v| exprUsesVar(v.*, var_name) else false,
        .assert_stmt => |a| blk: {
            if (exprUsesVar(a.condition.*, var_name)) break :blk true;
            if (a.msg) |m| {
                break :blk exprUsesVar(m.*, var_name);
            }
            break :blk false;
        },
        .raise_stmt => |r| blk: {
            if (r.exc) |e| {
                if (exprUsesVar(e.*, var_name)) break :blk true;
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
        .with_stmt => |w| blk: {
            if (exprUsesVar(w.context_expr.*, var_name)) break :blk true;
            for (w.body) |s| {
                if (stmtUsesVar(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .class_def => |class_def| blk: {
            // Check if variable is used in any method body (closure capture)
            // This handles: for x in items: class A: def f(self): return x
            for (class_def.body) |class_stmt| {
                if (class_stmt == .function_def) {
                    const method = class_stmt.function_def;
                    for (method.body) |method_stmt| {
                        if (stmtUsesVar(method_stmt, var_name)) break :blk true;
                    }
                }
            }
            break :blk false;
        },
        .function_def => |func_def| blk: {
            // Check if variable is used in nested function body
            for (func_def.body) |func_stmt| {
                if (stmtUsesVar(func_stmt, var_name)) break :blk true;
            }
            break :blk false;
        },
        .yield_stmt => |y| if (y.value) |v| exprUsesVar(v.*, var_name) else false,
        .yield_from_stmt => |yf| exprUsesVar(yf.value.*, var_name),
        .match_stmt => |m| blk: {
            if (exprUsesVar(m.subject.*, var_name)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |g| {
                    if (exprUsesVar(g.*, var_name)) break :blk true;
                }
                for (case.body) |s| {
                    if (stmtUsesVar(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if a variable is used in the loop body
pub fn varUsedInBody(body: []ast.Node, var_name: []const u8) bool {
    for (body) |stmt| {
        if (stmtUsesVar(stmt, var_name)) return true;
    }
    return false;
}

/// Check if a variable is reassigned in a list of statements
/// This is used to determine if tuple unpacking should use `var` instead of `const`
fn varIsReassignedInBody(body: []ast.Node, var_name: []const u8) bool {
    for (body) |stmt| {
        if (varIsReassignedInStmt(stmt, var_name)) return true;
    }
    return false;
}

/// Check if a variable is reassigned in a statement (appears as an assignment target)
fn varIsReassignedInStmt(stmt: ast.Node, var_name: []const u8) bool {
    return switch (stmt) {
        .assign => |a| blk: {
            for (a.targets) |target| {
                if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        .aug_assign => |a| a.target.* == .name and std.mem.eql(u8, a.target.name.id, var_name),
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            for (i.else_body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            if (f.orelse_body) |ob| {
                for (ob) |s| {
                    if (varIsReassignedInStmt(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            if (w.orelse_body) |ob| {
                for (ob) |s| {
                    if (varIsReassignedInStmt(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            for (t.handlers) |h| {
                for (h.body) |s| {
                    if (varIsReassignedInStmt(s, var_name)) break :blk true;
                }
            }
            for (t.else_body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            for (t.finalbody) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| {
                if (varIsReassignedInStmt(s, var_name)) break :blk true;
            }
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| {
                    if (varIsReassignedInStmt(s, var_name)) break :blk true;
                }
            }
            break :blk false;
        },
        else => false,
    };
}

/// Generate tuple unpacking for loop (e.g., for k, v in items)
fn genTupleUnpackLoop(self: *NativeCodegen, target: ast.Node, iter: ast.Node, body: []ast.Node) CodegenError!void {
    // Get target elements from either list or tuple
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => return error.UnsupportedSyntax, // Tuple unpacking requires list or tuple target
    };
    if (target_elts.len == 0) {
        return error.UnsupportedSyntax; // Tuple unpacking requires at least one variable
    }

    // Extract variable names - handle nested unpacking by using placeholder
    var var_names = try self.allocator.alloc([]const u8, target_elts.len);
    defer self.allocator.free(var_names);
    var has_nested = false;
    for (target_elts, 0..) |elt, i| {
        if (elt == .name) {
            var_names[i] = elt.name.id;
        } else {
            // Nested tuple unpacking (e.g., for a, (b, c) in items) - not fully supported
            // Use placeholder and emit warning comment
            var_names[i] = "_nested";
            has_nested = true;
        }
    }

    // If there's nested unpacking, we need to unpack in the loop body
    // For now, emit a warning that nested unpacking uses flat iteration
    if (has_nested) {
        try self.emitIndent();
        try self.emit("// Note: Nested tuple unpacking - inner tuples accessed via indices\n");
    }

    // Check if this is a lazy class attribute access (e.g., self.STRINGS where STRINGS is lazy)
    // If so, we need to wrap in a block to capture the runtime value first
    const lazy_attr_name = isLazyClassAttrAccess(self, iter);
    const needs_lazy_wrapper = lazy_attr_name != null;
    var em_lazy = self.exprEmitter();
    const lazy_iter_id = em_lazy.peekLabelId();
    if (needs_lazy_wrapper) {
        _ = em_lazy.reserveLabelId();
        try self.emitIndent();
        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __lazy_iter_{d} = try @This().{s}(__global_allocator);\n", .{ lazy_iter_id, lazy_attr_name.? });
    }

    // Check iter type first to determine if we need inline for
    const iter_type = try self.type_inferrer.inferExpr(iter);

    // Check if this is a method call like dict.items()
    const is_method_call = iter == .call and iter.call.func.* == .attribute;

    // Generate for loop over iterable
    try self.emitIndent();
    // Lazy iterators and tuples require inline for (comptime iteration)
    const needs_inline_for_loop = needs_lazy_wrapper or container_traits.isTuple(iter_type);
    if (needs_inline_for_loop) {
        try self.emit("inline for (");
    } else {
        try self.emit("for (");
    }

    // If using lazy wrapper, iterate over the captured variable
    if (needs_lazy_wrapper) {
        try self.output.writer(self.allocator).print("__lazy_iter_{d}", .{lazy_iter_id});
    } else if (container_traits.isList(iter_type)) {
        // Check if this is a slice subscript - slices return []T directly, not ArrayList
        const is_slice = if (iter == .subscript) blk: {
            const sub = iter.subscript;
            break :blk sub.slice == .slice;
        } else false;

        if (is_slice) {
            // Slice already returns []T - wrap in parens and iterate directly
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(")");
        } else if (is_method_call) {
            // Method call returns ArrayList - wrap in parens for .items
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else if (iter == .list) {
            // Inline list literal
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else if (producesBlockExpression(iter)) {
            // Block expression (reversed(), etc.) - wrap in temp variable for .items access
            // Can't do `blk: {...}.items` directly in for loop operand
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_iter: {{ const __iter = ", .{id});
            try self.genExpr(iter);
            try self.emitFmt("; break :__m{d}_iter __iter.items; }}", .{id});
        } else {
            // Variable that holds ArrayList
            try self.genExpr(iter);
            try self.emit(".items");
        }
    } else if (container_traits.isTuple(iter_type) and iter == .name) {
        // Tuple variable - must use inline for with direct iteration
        // Zig for loops can't iterate over tuple structs, need inline for
        // This is handled by switching to inline for at the loop level
        try self.genExpr(iter);
    } else if (iter == .name) {
        // Variable with unknown type - use container_dispatch helper to reduce monomorphization
        // Replaces inline @typeInfo/@hasField check with centralized helper
        try self.emit("runtime.container_dispatch.toIterSlice(@TypeOf(");
        try self.genExpr(iter);
        try self.emit("), ");
        try self.genExpr(iter);
        try self.emit(")");
    } else {
        // Not a list type - iterate directly
        try self.genExpr(iter);
    }

    // Use unique temp variable for tuple
    const unique_id = self.output.items.len;
    try self.output.writer(self.allocator).print(") |__tuple_{d}__| {{\n", .{unique_id});

    self.indent();
    try self.pushScope();

    // Track output position before generating unpacking - we'll check for actual usage after body gen
    const pre_body_pos = self.output.items.len;

    // Track declared variables for post-generation discard check
    var declared_vars = std.ArrayListUnmanaged([]const u8){};
    defer declared_vars.deinit(self.allocator);

    // Unpack tuple elements using struct field access: const x = __tuple__.@"0"; const y = __tuple__.@"1";
    // Escape variable names if they're Zig keywords (e.g., "fn" -> @"fn")
    // Handle Python's discard pattern: `for _, v in items:` - use `_ = value;` to discard
    // Also discard variables not used in the loop body to avoid unused variable errors
    // If a variable is later reassigned in the body, use `var` instead of `const`
    for (var_names, 0..) |var_name, i| {
        try self.emitIndent();
        // Check if this variable is used in the loop body (AST-based check)
        const is_used = varUsedInBody(body, var_name);
        if (std.mem.eql(u8, var_name, "_") or !is_used) {
            // Discard pattern or unused variable - explicitly discard the value
            try self.output.writer(self.allocator).print("_ = __tuple_{d}__.@\"{d}\";\n", .{ unique_id, i });
        } else {
            // Check if variable is hoisted (used after loop) - use assignment not declaration
            // Also check if reassigned later in the loop body - need `var` not `const`
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const is_reassigned = varIsReassignedInBody(body, var_name);

            if (is_hoisted) {
                // Already declared at function level - just assign using original name
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            } else {
                // Not hoisted - check if loop variable shadows a module-level function, imported module, or outer scope variable
                const shadows_outer_scope = self.isDeclared(var_name) or
                    self.module_level_funcs.contains(var_name) or self.imported_modules.contains(var_name);
                if (shadows_outer_scope and !self.var_renames.contains(var_name)) {
                    const renamed = try self.name_gen.local(var_name);
                    try self.var_renames.put(var_name, renamed);
                }
                const actual_name = self.var_renames.get(var_name) orelse var_name;

                // Check if the renamed name contains a dot (capture struct access like __cap_foo.bar)
                // If so, sanitize for declaration (replace dots with underscores)
                const decl_name = blk: {
                    if (std.mem.indexOfScalar(u8, actual_name, '.')) |_| {
                        var buf = try self.allocator.alloc(u8, actual_name.len);
                        for (actual_name, 0..) |c, idx| {
                            buf[idx] = if (c == '.') '_' else c;
                        }
                        break :blk buf;
                    } else {
                        break :blk actual_name;
                    }
                };

                if (is_reassigned) {
                    try self.emit("var ");
                } else {
                    try self.emit("const ");
                }
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), decl_name);

                // Track this variable for post-generation discard check
                try declared_vars.append(self.allocator, decl_name);
            }
            try self.output.writer(self.allocator).print(" = __tuple_{d}__.@\"{d}\";\n", .{ unique_id, i });

            // Mark the variable as declared so reassignment won't redeclare it
            if (!is_hoisted) try self.declareVar(var_name);
        }
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Post-generation check: emit discards for variables declared but not actually used in output
    // This catches cases where AST says var is used but codegen optimized it away (e.g., *arg expansion)
    const body_output = self.output.items[pre_body_pos..];
    for (declared_vars.items) |var_name| {
        // Count occurrences of the variable name as a complete identifier in the generated body
        var occurrence_count: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, body_output, pos, var_name)) |idx| {
            const end = idx + var_name.len;
            // Check boundaries for complete identifier match
            const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(body_output[idx - 1]) and body_output[idx - 1] != '_');
            const valid_end = end >= body_output.len or (!std.ascii.isAlphanumeric(body_output[end]) and body_output[end] != '_');
            if (valid_start and valid_end) {
                occurrence_count += 1;
                if (occurrence_count > 1) break; // Found usage beyond declaration
            }
            pos = end;
        }

        // If only 1 occurrence (the declaration itself), emit discard
        if (occurrence_count <= 1) {
            try self.emitIndent();
            try self.emit("_ = &");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.emit(";\n");
        }
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    // Close lazy wrapper block if we opened one
    if (needs_lazy_wrapper) {
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }
}

/// Generate for loop
pub fn genFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
    // Handle async for loops - these iterate over async iterators
    if (for_stmt.is_async) {
        try genAsyncFor(self, for_stmt);
        return;
    }

    // Set scope ID for scope-aware mutation tracking
    // Each loop body is a unique scope (using pointer address)
    const saved_scope_id = self.current_scope_id;
    self.current_scope_id = @intFromPtr(for_stmt.body.ptr);
    defer self.current_scope_id = saved_scope_id;

    // NOTE: Do NOT clear hoisted_vars here - they are function-level declarations
    // that persist throughout the entire function body. Clearing them would cause
    // assignments after the loop to redeclare variables with `var` instead of
    // using the hoisted declaration.

    // Check if iterating over a function call (range, enumerate, etc.)
    if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
        const func_name = for_stmt.iter.call.func.name.id;

        // Handle range() loops
        if (std.mem.eql(u8, func_name, "range")) {
            // range() requires single target variable
            const var_name = sanitizeVarName(for_stmt.target.name.id);
            try genRangeLoop(self, var_name, for_stmt.iter.call.args, for_stmt.body);
            return;
        }

        // Handle enumerate() loops
        if (std.mem.eql(u8, func_name, "enumerate")) {
            // enumerate() requires tuple target (idx, item)
            try genEnumerateLoop(self, for_stmt.target.*, for_stmt.iter.call.args, for_stmt.body);
            return;
        }

        // Handle zip() loops
        if (std.mem.eql(u8, func_name, "zip")) {
            try genZipLoop(self, for_stmt.target.*, for_stmt.iter.call.args, for_stmt.body);
            return;
        }
    }

    // Check if target is tuple unpacking (e.g., for k, v in dict.items())
    if (for_stmt.target.* == .list) {
        try genTupleUnpackLoop(self, for_stmt.target.*, for_stmt.iter.*, for_stmt.body);
        return;
    }
    // Also handle tuple target (e.g., for (r, g, b) in colors:)
    if (for_stmt.target.* == .tuple) {
        try genTupleUnpackLoop(self, for_stmt.target.*, for_stmt.iter.*, for_stmt.body);
        return;
    }

    // Regular iteration over collection - requires single target variable
    if (for_stmt.target.* != .name) {
        // Unsupported target type - generate compile error
        try self.emitIndent();
        try self.emit("@compileError(\"For loop target must be a simple variable name for this iterator type\");\n");
        return;
    }
    const var_name = sanitizeVarName(for_stmt.target.name.id);

    // Check iter type first (needed for tuple special case)
    const iter_type = try self.type_inferrer.inferExpr(for_stmt.iter.*);

    // Check if variable is used in body once (used for all patterns below)
    // Also check if variable is captured by a deferred closure
    const tuple_var_used = varUsedInBody(for_stmt.body, for_stmt.target.name.id) or
        self.deferred_closure_instantiations.contains(for_stmt.target.name.id);

    // Special case: tuple iteration requires inline for (comptime)
    // Python for-loop variables persist after the loop, so we declare before
    // and assign inside to make the variable available after the loop ends.
    if (container_traits.isTuple(iter_type)) {
        // Check if this is a tuple of TYPE REFERENCES (e.g., for T in (int, float, complex))
        // Type references in Python become Zig types (i64, f64, etc.) which can't be stored in runtime vars
        // In this case, skip variable declaration and use inline for capture variable directly
        const is_type_tuple = if (for_stmt.iter.* == .tuple) blk: {
            for (for_stmt.iter.tuple.elts) |elt| {
                if (elt != .name) break :blk false;
                const name = elt.name.id;
                // Check for Python type names that become Zig types
                if (!std.mem.eql(u8, name, "int") and
                    !std.mem.eql(u8, name, "float") and
                    !std.mem.eql(u8, name, "complex") and
                    !std.mem.eql(u8, name, "bool") and
                    !std.mem.eql(u8, name, "str") and
                    !std.mem.eql(u8, name, "bytes"))
                {
                    break :blk false;
                }
            }
            break :blk for_stmt.iter.tuple.elts.len > 0;
        } else false;

        // Check if this is a heterogeneous tuple (mixed types)
        // For heterogeneous tuples, we can't declare a single-typed variable
        // e.g., ("0", 0.0, 0j, (), [], {}, None, Rat, unittest) has string, float, complex, etc.
        // Also handles mixed int/bigint like (2**100, -2**100, 1, 37)
        const is_heterogeneous_tuple = if (iter_type.tuple.len > 1) blk: {
            const first_type = iter_type.tuple[0];
            const first_tag = @as(std.meta.Tag(@TypeOf(first_type)), first_type);
            for (iter_type.tuple[1..]) |elem_type| {
                const elem_tag = @as(std.meta.Tag(@TypeOf(elem_type)), elem_type);
                // Check for exact type tag mismatch (e.g., .int vs .bigint)
                // This catches mixed int/bigint tuples that isIntegral would miss
                if (first_tag != elem_tag) {
                    break :blk true;
                }
                // Also check type categories for broader compatibility
                const first_is_int = type_traits.isIntegral(first_type);
                const elem_is_int = type_traits.isIntegral(elem_type);
                const first_is_float = type_traits.isFloating(first_type);
                const elem_is_float = type_traits.isFloating(elem_type);
                const first_is_str = string_traits.isString(first_type);
                const elem_is_str = string_traits.isString(elem_type);
                const first_is_bool = type_traits.isBoolean(first_type);
                const elem_is_bool = type_traits.isBoolean(elem_type);
                // If categories don't match, it's heterogeneous
                if (first_is_int != elem_is_int or first_is_float != elem_is_float or
                    first_is_str != elem_is_str or first_is_bool != elem_is_bool)
                {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;

        // Check if tuple contains callable types (functions must be const in Zig)
        // First check via type inference
        var has_callable_elements = if (iter_type.tuple.len > 0) blk: {
            for (iter_type.tuple) |elem_type| {
                if (type_traits.isCallable(elem_type)) {
                    break :blk true;
                }
            }
            break :blk false;
        } else false;

        // Also check AST for known builtins that are callable (pow, operator.pow, operator.mod)
        // Type inference may not detect these as callable if they're unknown/dynamic
        if (!has_callable_elements and for_stmt.iter.* == .tuple) {
            const tuple_elts = for_stmt.iter.tuple.elts;
            for (tuple_elts) |elt| {
                if (elt == .name) {
                    const name = elt.name.id;
                    // pow is a callable builtin function
                    if (std.mem.eql(u8, name, "pow")) {
                        has_callable_elements = true;
                        break;
                    }
                } else if (elt == .attribute) {
                    const attr = elt.attribute;
                    if (attr.value.* == .name) {
                        const mod_name = attr.value.name.id;
                        // operator.pow and operator.mod are callable structs
                        if (std.mem.eql(u8, mod_name, "operator")) {
                            if (std.mem.eql(u8, attr.attr, "pow") or std.mem.eql(u8, attr.attr, "mod")) {
                                has_callable_elements = true;
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Declare variable before loop so it persists after (Python semantics)
        // Only declare if not already declared in current scope (handles reuse like `for index in ...` twice)
        // Also skip if variable was hoisted at function start (avoids redeclaration)
        // Skip for type tuples - types can't be stored in runtime variables
        // Skip for heterogeneous tuples - can't use a single type for mixed-type elements
        // Skip for callable tuples - function types must be const in Zig
        if (!is_type_tuple and !is_heterogeneous_tuple and !has_callable_elements and !self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
            try self.emitIndent();
            try self.emit("var ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            // Determine loop variable type - use concrete type to avoid comptime_int issues
            // For tuples of all ints, use i64. For booleans, use bool. For strings, use []const u8.
            // String literals have length-encoded types (e.g., *const [0:0]u8, *const [1:0]u8)
            // so we must use []const u8 to allow different lengths.
            if (iter_type.tuple.len > 0) {
                const first_elem_type = iter_type.tuple[0];
                if (type_traits.isIntegral(first_elem_type)) {
                    try self.emit(": i64 = undefined;\n");
                } else if (type_traits.isBoolean(first_elem_type)) {
                    try self.emit(": bool = undefined;\n");
                } else if (type_traits.isFloating(first_elem_type)) {
                    try self.emit(": f64 = undefined;\n");
                } else if (string_traits.isString(first_elem_type)) {
                    // String literals have length in type - use []const u8 for flexibility
                    try self.emit(": []const u8 = undefined;\n");
                } else {
                    // Use std.meta.Elem to safely extract element type (works on empty arrays)
                    try self.emit(": std.meta.Elem(@TypeOf(");
                    try self.genExpr(for_stmt.iter.*);
                    try self.emit(")) = undefined;\n");
                }
            } else {
                // Empty tuple - use i64 as default
                try self.emit(": i64 = undefined;\n");
            }
            try self.declareVar(var_name);
        }

        // Use unique loop capture variable name to avoid shadowing in nested loops
        const loop_var_id = self.lambda_counter;
        self.lambda_counter += 1;

        try self.emitIndent();
        try self.emit("inline for (");
        try self.genExpr(for_stmt.iter.*);
        try self.output.writer(self.allocator).print(") |__loop_val_{d}| {{\n", .{loop_var_id});

        self.indent();
        try self.pushScope();

        // Track pending_discards keys before entering loop body
        // Variables assigned inside inline for are block-scoped and shouldn't get function-level discards
        var pending_keys_before = std.ArrayList([]const u8){};
        defer pending_keys_before.deinit(self.allocator);
        {
            var iter = self.pending_discards.iterator();
            while (iter.next()) |entry| {
                try pending_keys_before.append(self.allocator, entry.key_ptr.*);
            }
        }

        // For type tuples, create a const alias (types must be comptime)
        // For heterogeneous tuples, also use const (can't assign different types to one var)
        // For homogeneous value tuples, assign to outer variable so it persists after loop
        // Check is_type_tuple from earlier detection
        const is_type_tuple_inner = if (for_stmt.iter.* == .tuple) inner_blk: {
            for (for_stmt.iter.tuple.elts) |elt| {
                if (elt != .name) break :inner_blk false;
                const name = elt.name.id;
                if (!std.mem.eql(u8, name, "int") and
                    !std.mem.eql(u8, name, "float") and
                    !std.mem.eql(u8, name, "complex") and
                    !std.mem.eql(u8, name, "bool") and
                    !std.mem.eql(u8, name, "str") and
                    !std.mem.eql(u8, name, "bytes"))
                {
                    break :inner_blk false;
                }
            }
            break :inner_blk for_stmt.iter.tuple.elts.len > 0;
        } else false;

        // Re-check heterogeneous using the same logic as above
        // Also handles mixed int/bigint like (2**100, -2**100, 1, 37)
        const is_heterogeneous_inner = if (iter_type.tuple.len > 1) inner_blk: {
            const first_type = iter_type.tuple[0];
            const first_tag = @as(std.meta.Tag(@TypeOf(first_type)), first_type);
            for (iter_type.tuple[1..]) |elem_type| {
                const elem_tag = @as(std.meta.Tag(@TypeOf(elem_type)), elem_type);
                // Check for exact type tag mismatch (e.g., .int vs .bigint)
                if (first_tag != elem_tag) {
                    break :inner_blk true;
                }
                const first_is_int = type_traits.isIntegral(first_type);
                const elem_is_int = type_traits.isIntegral(elem_type);
                const first_is_float = type_traits.isFloating(first_type);
                const elem_is_float = type_traits.isFloating(elem_type);
                const first_is_str = string_traits.isString(first_type);
                const elem_is_str = string_traits.isString(elem_type);
                const first_is_bool = type_traits.isBoolean(first_type);
                const elem_is_bool = type_traits.isBoolean(elem_type);
                if (first_is_int != elem_is_int or first_is_float != elem_is_float or
                    first_is_str != elem_is_str or first_is_bool != elem_is_bool)
                {
                    break :inner_blk true;
                }
            }
            break :inner_blk false;
        } else false;

        // Check if variable is already declared (from previous loop or hoisting)
        // If so, we can't use `const var` as it would shadow the outer declaration
        const var_already_declared = self.isDeclared(var_name) or self.hoisted_vars.contains(var_name);

        // Track if we need to temporarily remove var from func_local_vars for rename to take effect
        // In expressions.zig, func_local_vars is checked BEFORE var_renames, so we need to
        // temporarily remove the var from func_local_vars during the loop body
        var removed_from_func_locals = false;

        try self.emitIndent();
        if (is_type_tuple_inner or is_heterogeneous_inner or has_callable_elements) {
            if (var_already_declared) {
                // Variable already declared - use unique name to avoid shadowing
                // Register rename so loop body uses the unique name
                const unique_name = try std.fmt.allocPrint(self.allocator, "__inner_{s}_{d}", .{ var_name, loop_var_id });
                try self.var_renames.put(var_name, unique_name);
                // Temporarily remove from func_local_vars so rename takes effect in expressions.zig
                if (self.func_local_vars.swapRemove(var_name)) {
                    removed_from_func_locals = true;
                }
                // For heterogeneous tuples (not type or callable), wrap in PyValue for type consistency
                // This allows TryHelper to use concrete runtime.PyValue type instead of anytype
                if (is_heterogeneous_inner and !is_type_tuple_inner and !has_callable_elements) {
                    try self.output.writer(self.allocator).print("const __inner_{s}_{d}: runtime.PyValue = runtime.PyValue.from(__loop_val_{d});\n", .{ var_name, loop_var_id, loop_var_id });
                    try self.heterogeneous_loop_vars.put(var_name, {});
                } else {
                    try self.output.writer(self.allocator).print("const __inner_{s}_{d} = __loop_val_{d};\n", .{ var_name, loop_var_id, loop_var_id });
                }
            } else {
                // For type tuples, heterogeneous tuples, and callable tuples: const var = __loop_val_N
                // Types must be comptime, heterogeneous values can't share a single type,
                // and function types must be const in Zig
                // For heterogeneous tuples (not type or callable), wrap in PyValue for type consistency
                if (is_heterogeneous_inner and !is_type_tuple_inner and !has_callable_elements) {
                    try self.emit("const ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                    try self.output.writer(self.allocator).print(": runtime.PyValue = runtime.PyValue.from(__loop_val_{d});\n", .{loop_var_id});
                    try self.heterogeneous_loop_vars.put(var_name, {});
                } else {
                    try self.emit("const ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                    try self.output.writer(self.allocator).print(" = __loop_val_{d};\n", .{loop_var_id});
                }
            }
        } else {
            // For homogeneous value tuples: T = __loop_val_N (runtime assignment to outer var)
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.output.writer(self.allocator).print(" = __loop_val_{d};\n", .{loop_var_id});
        }

        // Register loop variable type as widened tuple element type
        // This allows type inference inside the loop body to know f's type
        if (iter_type.tuple.len > 0) {
            var elem_type = iter_type.tuple[0];
            for (iter_type.tuple[1..]) |t| {
                elem_type = elem_type.widen(t);
            }
            // For heterogeneous tuples, register as pyvalue since we wrap in PyValue
            if (is_heterogeneous_inner and !is_type_tuple_inner and !has_callable_elements) {
                try self.type_inferrer.putScopedVar(for_stmt.target.name.id, .pyvalue);
            } else {
                try self.type_inferrer.putScopedVar(for_stmt.target.name.id, elem_type);
            }

            // If any tuple element is a callable type, register loop variable as callable
            // This enables .call() syntax for calls like pow_op(a, b) -> pow_op.call(a, b)
            // where the tuple is (pow, operator.pow) - both callable structs
            if (type_traits.isCallable(elem_type)) {
                const owned_name = try self.arena.allocator().dupe(u8, var_name);
                try self.callable_vars.put(owned_name, {});
            }
        }

        // Check if iterating over tuple containing callable builtin references
        // e.g., for pow_op in pow, operator.pow:
        // Both pow and operator.pow are callable structs, need .call() syntax
        if (for_stmt.iter.* == .tuple) {
            const tuple_elts = for_stmt.iter.tuple.elts;
            var has_pow = false;
            for (tuple_elts) |elt| {
                // Check for builtin references: pow, operator.pow, etc.
                if (elt == .name) {
                    const name = elt.name.id;
                    if (std.mem.eql(u8, name, "pow")) {
                        // Loop variable iterates over callable structs
                        const owned_name = try self.arena.allocator().dupe(u8, var_name);
                        try self.callable_vars.put(owned_name, {});
                        has_pow = true;
                        break;
                    }
                } else if (elt == .attribute) {
                    const attr = elt.attribute;
                    if (attr.value.* == .name) {
                        const mod_name = attr.value.name.id;
                        if (std.mem.eql(u8, mod_name, "operator")) {
                            if (std.mem.eql(u8, attr.attr, "pow") or std.mem.eql(u8, attr.attr, "mod")) {
                                // Loop variable iterates over callable structs
                                const owned_name = try self.arena.allocator().dupe(u8, var_name);
                                try self.callable_vars.put(owned_name, {});
                                if (std.mem.eql(u8, attr.attr, "pow")) {
                                    has_pow = true;
                                }
                                break;
                            }
                        }
                    }
                }
            }
            // pow returns error union for ZeroDivisionError
            if (has_pow) {
                const owned_name2 = try self.arena.allocator().dupe(u8, var_name);
                try self.error_callable_vars.put(owned_name2, {});
            }
        }

        // No longer need @TypeOf reference since we assign __loop_val to outer var

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Emit discards for unused variables inside inline for before scope exits
        // This is critical because inline for body is comptime-unrolled and each
        // iteration needs its own discard handling
        try self.emitScopedDiscards();

        self.popScope();

        // Remove any pending_discards that were added during the inline for body
        // These variables are block-scoped and not accessible at function end
        {
            var keys_to_remove = std.ArrayList([]const u8){};
            defer keys_to_remove.deinit(self.allocator);
            var iter = self.pending_discards.iterator();
            while (iter.next()) |entry| {
                // Check if this key existed before entering the loop body
                var existed_before = false;
                for (pending_keys_before.items) |before_key| {
                    if (std.mem.eql(u8, entry.key_ptr.*, before_key)) {
                        existed_before = true;
                        break;
                    }
                }
                if (!existed_before) {
                    try keys_to_remove.append(self.allocator, entry.key_ptr.*);
                }
            }
            for (keys_to_remove.items) |key| {
                _ = self.pending_discards.swapRemove(key);
            }
        }

        // Clean up var_renames that were added for shadowing avoidance
        _ = self.var_renames.swapRemove(var_name);
        // Clean up heterogeneous loop var tracking
        _ = self.heterogeneous_loop_vars.swapRemove(var_name);

        // Restore func_local_vars if we removed it for rename to take effect
        if (removed_from_func_locals) {
            try self.func_local_vars.put(var_name, {});
        }

        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Regular iteration over collection
    try self.emitIndent();

    // Handle dict iteration - iterate over .keys()
    if (container_traits.isDict(iter_type)) {
        try self.emit("for (");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(".keys()) |");

        // If capture would shadow a hoisted variable, use a unique capture name
        const shadows_hoisted = self.hoisted_vars.contains(var_name);
        const capture_name = if (shadows_hoisted)
            try std.fmt.allocPrint(self.allocator, "__cap_{s}_{d}", .{ var_name, self.output.items.len })
        else
            var_name;

        if (!tuple_var_used) {
            try self.emit("_");
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
        }
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

        // If we renamed the capture, assign to the hoisted variable
        if (shadows_hoisted and tuple_var_used) {
            try self.emitIndent();
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.emit(" = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
            try self.emit(";\n");
        }

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Handle file iteration - read lines using while loop with runtime.PyFile.readlines
    // Python: for line in file: -> Zig: for ((try runtime.PyFile.readlines(file, alloc)).items) |line|
    if (iter_type == .file) {
        // Generate: for ((try runtime.PyFile.readlines(file, allocator)).items) |line| {
        try self.emit("for ((try runtime.PyFile.readlines(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(", __global_allocator)).items) |");
        if (!tuple_var_used) {
            try self.emit("_");
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        }
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

        // Register loop variable as string type (runtime since from file)
        // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
        try self.type_inferrer.putScopedVar(var_name, .{ .string = .runtime });

        // Track loop capture variable for shadowing detection
        // When Python code does `line = line.strip()` inside `for line in file:`,
        // we need to rename the new variable to avoid shadowing the immutable Zig capture
        if (tuple_var_used) {
            try self.loop_capture_vars.put(var_name, {});
        }

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Clean up loop capture tracking and renames when exiting loop
        _ = self.loop_capture_vars.swapRemove(var_name);
        _ = self.var_renames.swapRemove(var_name);
        _ = self.heterogeneous_loop_vars.swapRemove(var_name);

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Handle string iteration - Python yields single-char strings, Zig yields bytes
    // Convert to index-based iteration that yields single-char slices
    if (string_traits.isString(iter_type)) {
        // Generate: { const __str = <expr>; for (0..__str.len) |__i| { const c = __str[__i..][0..1]; ... } }
        var em_str = self.exprEmitter();
        const label_id = em_str.reserveLabelId();

        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __str_{d} = ", .{label_id});
        try self.genExpr(for_stmt.iter.*);
        try self.emit(";\n");

        try self.emitIndent();
        try self.output.writer(self.allocator).print("for (0..__str_{d}.len) |__i_{d}| {{\n", .{ label_id, label_id });

        self.indent();
        try self.pushScope();

        // Declare the loop variable as a single-char slice
        try self.emitIndent();
        if (!tuple_var_used) {
            try self.emit("_ = ");
            try self.output.writer(self.allocator).print("__str_{d}[__i_{d}..][0..1];\n", .{ label_id, label_id });
        } else {
            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.output.writer(self.allocator).print(" = __str_{d}[__i_{d}..][0..1];\n", .{ label_id, label_id });
        }

        // Register loop variable as string type (slice from indexing)
        // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
        try self.type_inferrer.putScopedVar(var_name, .{ .string = .slice });

        // Track loop capture variable
        if (tuple_var_used) {
            try self.loop_capture_vars.put(var_name, {});
        }

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Clean up
        _ = self.loop_capture_vars.swapRemove(var_name);
        _ = self.var_renames.swapRemove(var_name);
        _ = self.heterogeneous_loop_vars.swapRemove(var_name);

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // TWO-FLOW: Handle PyValue iteration (uncertain types)
    // PyValue.list is *ArrayListUnmanaged(PyValue) - need .items to get slice
    // For iteration, extract items from the ArrayList pointer
    if (iter_type == .pyvalue) {
        // Generate: for (iter.list.items) |item| { ... } or runtime dispatch
        var em_pyval = self.exprEmitter();
        const label_id = em_pyval.reserveLabelId();

        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __pyval_{d} = ", .{label_id});
        try self.genExpr(for_stmt.iter.*);
        try self.emit(";\n");
        try self.emitIndent();
        // Use runtime.container_dispatch.toIterSlice() - compiles ONCE per type, not per call site
        try self.output.writer(self.allocator).print(
            "const __pyval_items_{d} = runtime.container_dispatch.toIterSlice(@TypeOf(__pyval_{d}), __pyval_{d});\n",
            .{ label_id, label_id, label_id },
        );

        // Check if loop variable would shadow an outer scope variable
        const shadows_outer_pyval = self.isDeclared(var_name) or self.hoisted_vars.contains(var_name) or
            self.module_level_funcs.contains(var_name) or self.imported_modules.contains(var_name);
        const unique_capture_id_pyval = em_pyval.peekLabelId();
        if (shadows_outer_pyval) _ = em_pyval.reserveLabelId();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("for (__pyval_items_{d}) |", .{label_id});
        if (!tuple_var_used) {
            try self.emit("_");
        } else if (shadows_outer_pyval) {
            // Use unique capture name to avoid shadowing
            try self.output.writer(self.allocator).print("__loop_{s}_{d}__", .{ var_name, unique_capture_id_pyval });
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        }
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

        // If we used a unique capture name, assign to outer variable (Python semantics)
        if (tuple_var_used and shadows_outer_pyval) {
            try self.emitIndent();
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.output.writer(self.allocator).print(" = __loop_{s}_{d}__;\n", .{ var_name, unique_capture_id_pyval });
        }

        // Register loop variable type as pyvalue (element of PyValue list)
        try self.type_inferrer.putScopedVar(for_stmt.target.name.id, .pyvalue);

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Handle vararg parameter iteration (e.g., for c in *classes)
    // Varargs are passed as &.{...} (pointer to tuple) at call sites
    // Must dereference and use inline for to iterate over fields at comptime
    // This is necessary because tuple elements can be different types (class types)
    if (for_stmt.iter.* == .name) {
        const iter_name = for_stmt.iter.name.id;
        if (self.vararg_params.contains(iter_name)) {
            // Generate comptime iteration over tuple fields:
            // First check if it's a pointer type (call site passes &.{...})
            // const __vararg_val = if (@typeInfo(@TypeOf(vararg)) == .pointer) vararg.* else vararg;
            // inline for (@typeInfo(@TypeOf(__vararg_val)).@"struct".fields) |field| {
            //     const c = @field(__vararg_val, field.name);
            //     ...body...
            // }
            try self.emit("{\n");
            self.indent();
            try self.emitIndent();
            // Handle both pointer and direct tuple types
            try self.output.writer(self.allocator).print(
                "const __vararg_val_{s} = if (@typeInfo(@TypeOf({s})) == .pointer) {s}.* else {s};\n",
                .{ iter_name, iter_name, iter_name, iter_name },
            );
            try self.emitIndent();
            try self.output.writer(self.allocator).print(
                "inline for (@typeInfo(@TypeOf(__vararg_val_{s})).@\"struct\".fields) |__tuple_field| {{\n",
                .{iter_name},
            );
            self.indent();
            try self.pushScope();

            try self.emitIndent();
            // Check if variable is hoisted - if so, use original name without redeclaration
            const is_hoisted_vararg = self.hoisted_vars.contains(var_name);
            const actual_name_vararg = if (is_hoisted_vararg) blk: {
                // Hoisted vars use original name
                break :blk var_name;
            } else blk: {
                // Not hoisted - check if loop variable shadows outer scope
                const shadows_outer_scope_vararg = self.isDeclared(var_name) or
                    self.module_level_funcs.contains(var_name) or self.imported_modules.contains(var_name);
                if (shadows_outer_scope_vararg and !self.var_renames.contains(var_name)) {
                    const renamed = try self.name_gen.local(var_name);
                    try self.var_renames.put(var_name, renamed);
                }
                break :blk self.var_renames.get(var_name) orelse var_name;
            };

            if (!is_hoisted_vararg) {
                try self.emit("const ");
            }
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name_vararg);
            try self.output.writer(self.allocator).print(
                " = @field(__vararg_val_{s}, __tuple_field.name);\n",
                .{iter_name},
            );

            // Register loop variable type as unknown (comptime types can vary)
            try self.type_inferrer.putScopedVar(for_stmt.target.name.id, .unknown);

            // Track this variable as coming from vararg iteration
            // Used by call codegen to generate c.init(...) instead of c(...)
            try self.vararg_loop_vars.put(actual_name_vararg, {});

            // Scan loop body for .append() calls to track lists populated from vararg
            // This allows starred expression unpacking to use the correct tuple type
            for (for_stmt.body) |stmt| {
                if (stmt == .expr_stmt) {
                    if (stmt.expr_stmt.value.* == .call) {
                        const call_expr = stmt.expr_stmt.value.call;
                        if (call_expr.func.* == .attribute) {
                            const attr = call_expr.func.attribute;
                            // Check for list.append() pattern
                            if (std.mem.eql(u8, attr.attr, "append")) {
                                if (attr.value.* == .name) {
                                    const list_name = attr.value.name.id;
                                    try self.vararg_list_sources.put(list_name, iter_name);
                                }
                            }
                        }
                    }
                }
            }

            // Track current vararg source for detecting append to lists
            // This allows starred expression unpacking to use the correct tuple type
            const prev_vararg_source = self.current_vararg_source;
            self.current_vararg_source = iter_name;

            for (for_stmt.body) |stmt| {
                try self.generateStmt(stmt);
            }

            // Restore previous vararg source (for nested loops)
            self.current_vararg_source = prev_vararg_source;

            // Remove tracking after loop body
            _ = self.vararg_loop_vars.swapRemove(actual_name_vararg);

            self.popScope();
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");

            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            return;
        }
    }

    // Handle PyObject/PyValue iteration (e.g., from json.load() returning PyList)
    // Two-Flow: Include .pyvalue for uncertain iterable types
    // Use while loop with runtime.PyList.getItem() since we can't use Zig for-each on PyObject
    if (type_traits.isUnknown(iter_type) or iter_type == .pyvalue) {
        // Generate: var __i: usize = 0; const __len = runtime.PyList.len(iter);
        //           while (__i < __len) : (__i += 1) { const var = try runtime.PyList.getItem(iter, __i); ... }
        var em_pylist = self.exprEmitter();
        const label_id = em_pylist.reserveLabelId();

        try self.emit("{\n");
        self.indent();
        // Handle error unions (e.g., generator functions that return ![]PyValue)
        // First capture raw value, then unwrap if it's an error union
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __pylist_raw_{d} = ", .{label_id});
        try self.genExpr(for_stmt.iter.*);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print(
            "const __pylist_{d} = if (@typeInfo(@TypeOf(__pylist_raw_{d})) == .error_union) try __pylist_raw_{d} else __pylist_raw_{d};\n",
            .{ label_id, label_id, label_id, label_id },
        );
        try self.emitIndent();
        // Use runtime.container_dispatch.getLen() - compiles ONCE per type, not per call site
        // Handles: slices, arrays, ArrayLists, PyBytes, and PyObject
        try self.output.writer(self.allocator).print(
            "const __pylist_len_{d} = runtime.container_dispatch.getLen(@TypeOf(__pylist_{d}), __pylist_{d});\n",
            .{ label_id, label_id, label_id },
        );
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var __pylist_i_{d}: usize = 0;\n", .{label_id});
        try self.emitIndent();
        try self.output.writer(self.allocator).print("while (__pylist_i_{d} < __pylist_len_{d}) : (__pylist_i_{d} += 1) {{\n", .{ label_id, label_id, label_id });

        self.indent();
        try self.pushScope();

        // Use runtime.container_dispatch.getAt() - compiles ONCE per type, not per call site
        // Handles: slices, arrays, ArrayLists, PyBytes, and PyObject
        try self.emitIndent();
        const get_item_expr = "runtime.container_dispatch.getAt(@TypeOf(__pylist_{d}), __pylist_{d}, __pylist_i_{d})";
        if (!tuple_var_used) {
            try self.output.writer(self.allocator).print("_ = " ++ get_item_expr ++ ";\n", .{ label_id, label_id, label_id });
        } else {
            // Check if variable is hoisted (used after loop) - use assignment not const
            // Hoisted vars are already declared in outer scope, so don't rename them
            if (self.hoisted_vars.contains(var_name)) {
                // Use original var name (already declared in outer scope)
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                try self.output.writer(self.allocator).print(" = " ++ get_item_expr ++ ";\n", .{ label_id, label_id, label_id });
            } else {
                // Not hoisted - check if loop variable shadows a module-level function, imported module, or outer scope variable
                const shadows_outer_scope = self.isDeclared(var_name) or
                    self.module_level_funcs.contains(var_name) or self.imported_modules.contains(var_name);
                if (shadows_outer_scope and !self.var_renames.contains(var_name)) {
                    const renamed = try self.name_gen.local(var_name);
                    try self.var_renames.put(var_name, renamed);
                }
                const actual_name = self.var_renames.get(var_name) orelse var_name;

                // Check if the renamed name contains a dot (capture struct access like __cap_foo.bar)
                // If so, sanitize for declaration (replace dots with underscores)
                const decl_name = blk: {
                    if (std.mem.indexOfScalar(u8, actual_name, '.')) |_| {
                        // Contains dot - sanitize for declaration
                        var buf = try self.allocator.alloc(u8, actual_name.len);
                        for (actual_name, 0..) |c, idx| {
                            buf[idx] = if (c == '.') '_' else c;
                        }
                        break :blk buf;
                    } else {
                        break :blk actual_name;
                    }
                };

                try self.emit("const ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), decl_name);
                try self.output.writer(self.allocator).print(" = " ++ get_item_expr ++ ";\n", .{ label_id, label_id, label_id });
            }
        }

        // Register loop variable type as unknown (PyObject)
        try self.type_inferrer.putScopedVar(for_stmt.target.name.id, .unknown);

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    try self.emit("for (");

    // Check if this is a constant list (will be compiled to array, not ArrayList)
    const is_constant_array = blk: {
        if (for_stmt.iter.* == .list) {
            const list = for_stmt.iter.list;
            // Check if it's a constant homogeneous list (becomes array)
            if (list.elts.len > 0) {
                var all_constants = true;
                for (list.elts) |elem| {
                    if (elem != .constant) {
                        all_constants = false;
                        break;
                    }
                }
                if (all_constants) {
                    // Check if all same type
                    const first_type = @as(std.meta.Tag(@TypeOf(list.elts[0].constant.value)), list.elts[0].constant.value);
                    var all_same = true;
                    for (list.elts[1..]) |elem| {
                        const elem_type = @as(std.meta.Tag(@TypeOf(elem.constant.value)), elem.constant.value);
                        if (elem_type != first_type) {
                            all_same = false;
                            break;
                        }
                    }
                    break :blk all_same;
                }
            }
        }
        break :blk false;
    };

    // Check if we're iterating over a variable that holds a constant array
    const is_array_var = blk: {
        if (for_stmt.iter.* == .name) {
            const iter_var_name = for_stmt.iter.name.id;
            break :blk self.isArrayVar(iter_var_name);
        }
        break :blk false;
    };

    // If iterating over constant array literal or array variable, no .items needed
    // If iterating over ArrayList (variable or inline), add .items
    if (is_constant_array or is_array_var) {
        // Constant array or array variable - iterate directly
        try self.genExpr(for_stmt.iter.*);
    } else if (container_traits.isList(iter_type) and for_stmt.iter.* == .list) {
        // Inline ArrayList literal - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else if (container_traits.isList(iter_type) and for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
        // Method call that returns ArrayList - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else if ((container_traits.isList(iter_type) or iter_type == .deque) and for_stmt.iter.* == .call) {
        // Function call that returns ArrayList (like chain(a, b)) - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else {
        // ArrayList (list or deque types) need .items for iteration
        // Block expressions (listcomp, etc.) need to be wrapped in a temp variable
        if (container_traits.isList(iter_type) or iter_type == .deque) {
            // Check if this is a slice subscript - slices return []T directly, not ArrayList
            const is_slice = if (for_stmt.iter.* == .subscript) blk: {
                const sub = for_stmt.iter.subscript;
                // Slice has .slice variant with SliceRange, index has .index variant
                break :blk sub.slice == .slice;
            } else false;

            if (is_slice) {
                // Slice already returns []T - wrap in parens and iterate directly
                try self.emit("(");
                try self.genExpr(for_stmt.iter.*);
                try self.emit(")");
            } else if (producesBlockExpression(for_stmt.iter.*)) {
                // Wrap block expression: blk: { const __iter = <expr>; break :blk __iter.items; }
                const id = self.nextNameId();
                try self.emitFmt("__m{d}_iter: {{ const __iter = ", .{id});
                try self.genExpr(for_stmt.iter.*);
                try self.emitFmt("; break :__m{d}_iter __iter.items; }}", .{id});
            } else {
                try self.genExpr(for_stmt.iter.*);
                try self.emit(".items");
            }
        } else if (for_stmt.iter.* == .name) {
            // Variable with unknown type - use container_dispatch helper to reduce monomorphization
            // Replaces inline @typeInfo/@hasField check with centralized helper
            try self.emit("runtime.container_dispatch.toIterSlice(@TypeOf(");
            try self.genExpr(for_stmt.iter.*);
            try self.emit("), ");
            try self.genExpr(for_stmt.iter.*);
            try self.emit(")");
        } else {
            try self.genExpr(for_stmt.iter.*);
        }
    }

    // Check if variable is used in body - if not, use _ to avoid unused capture error
    // Also check if variable is captured by a deferred closure (closure defined before this for-loop
    // that captures the loop variable - needs the loop variable to be assigned for instantiation)
    const var_used = varUsedInBody(for_stmt.body, for_stmt.target.name.id) or
        self.deferred_closure_instantiations.contains(for_stmt.target.name.id);

    // Check if this variable already exists in outer scope (Python allows reusing loop vars)
    // If so, use a unique capture name to avoid Zig "capture shadows local" error
    // Also check hoisted_vars - hoisted vars are pre-declared at function start
    // Also check imported_modules - can't shadow an imported module name
    // Also check func_local_vars - can't shadow function local variables
    // Use raw name for hoisted_vars check (scope_analyzer uses raw names)
    // NOTE: Only check variables that are ACTUALLY declared (isDeclared, hoisted_vars, imported_modules)
    // Do NOT include func_local_vars - those are variables that WILL be declared later,
    // and assigning to them before declaration causes "undeclared identifier" errors
    const raw_var_name = for_stmt.target.name.id;
    const shadows_outer = self.isDeclared(raw_var_name) or self.hoisted_vars.contains(raw_var_name) or self.imported_modules.contains(raw_var_name);
    var em_capture = self.exprEmitter();
    const unique_capture_id = em_capture.peekLabelId();
    if (shadows_outer) _ = em_capture.reserveLabelId();

    try self.emit(") |");
    if (!var_used) {
        // Use bare _ for unused capture (Zig requires this)
        try self.emit("_");
    } else if (shadows_outer) {
        // Use unique capture name to avoid shadowing
        try self.output.writer(self.allocator).print("__loop_{s}_{d}__", .{ var_name, unique_capture_id });
    } else {
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
    }
    try self.emit("| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // If we used a unique capture name due to shadowing, assign it to the outer variable
    // This implements Python semantics where `for x in ...` reassigns x from outer scope
    if (var_used and shadows_outer) {
        try self.emitIndent();
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);

        // Check if target variable is typed as BigInt - need to convert loop capture
        // This handles cases like: for n in [324, 2**100] where n is BigInt but loop yields i64
        const var_type = self.type_inferrer.var_types.get(var_name);
        const is_bigint_target = self.bigint_vars.contains(var_name) or
            (var_type != null and var_type.? == .bigint);

        if (is_bigint_target) {
            try self.output.writer(self.allocator).print(" = (runtime.BigInt.fromInt(__global_allocator, __loop_{s}_{d}__) catch unreachable);\n", .{ var_name, unique_capture_id });
        } else {
            try self.output.writer(self.allocator).print(" = __loop_{s}_{d}__;\n", .{ var_name, unique_capture_id });
        }
        // Trigger any deferred closures waiting on this variable
        // This handles closures defined before the for-loop that capture the loop variable
        try triggerDeferredClosureInstantiations(self, for_stmt.target.name.id);
    }

    // If the loop variable is captured by a nested class but not directly used,
    // emit `_ = varname;` to suppress unused warning while keeping it available for captures
    if (!var_used and self.nested_class_captures.count() > 0) {
        // Check if any nested class captures this variable
        var iter = self.nested_class_captures.iterator();
        var is_captured = false;
        while (iter.next()) |entry| {
            for (entry.value_ptr.*) |cap| {
                if (std.mem.eql(u8, cap, for_stmt.target.name.id)) {
                    is_captured = true;
                    break;
                }
            }
            if (is_captured) break;
        }
        if (is_captured) {
            try self.emitIndent();
            try self.emit("_ = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.emit(";\n");
        }
    }

    // Track loop capture variable for shadowing detection
    // When Python code does `line = line.strip()` inside `for line in file:`,
    // we need to rename the new variable to avoid shadowing the immutable Zig capture
    if (var_used) {
        try self.loop_capture_vars.put(var_name, {});
    }

    // If iterating over a vararg param (e.g., args in *args), register loop var as i64
    // This enables correct type inference for print(x) inside the loop
    // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
    if (for_stmt.iter.* == .name) {
        const iter_var_name = for_stmt.iter.name.id;
        if (self.vararg_params.contains(iter_var_name)) {
            // Register loop variable as i64 type
            try self.type_inferrer.putScopedVar(var_name, .{ .int = .bounded });
        }
    }

    // If iterating over a deque (ArrayList from itertools, etc.), loop variable is i64
    if (iter_type == .deque) {
        try self.type_inferrer.putScopedVar(var_name, .{ .int = .bounded });
    }

    // If iterating over a list of callables (PyCallable), register loop var as callable
    // This enables .call() syntax for calls like f(arg) -> f.call(arg)
    // Also register in var_types for type inference of call return values
    if (container_traits.isList(iter_type)) {
        if (type_traits.isCallable(iter_type.list.*)) {
            // Register loop variable as callable for .call() generation
            const owned_name = try self.arena.allocator().dupe(u8, var_name);
            try self.callable_vars.put(owned_name, {});
            // Register in var_types for type inference
            // Use .unknown since we can't know the return type of arbitrary callables in a list
            try self.type_inferrer.putScopedVar(var_name, .{ .callable = .unknown });
        }
    }

    for (for_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Clean up loop capture tracking and renames when exiting loop
    _ = self.loop_capture_vars.swapRemove(var_name);
    _ = self.var_renames.swapRemove(var_name);
    _ = self.heterogeneous_loop_vars.swapRemove(var_name);

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    // Handle optional else clause (for/else)
    // Note: In Python, else runs if loop completes without break.
    // For now, we emit it unconditionally (correct for loops without break)
    if (for_stmt.orelse_body) |else_body| {
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }
}

/// Generate range() loop as Zig while loop
fn genRangeLoop(self: *NativeCodegen, var_name: []const u8, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // range(stop) or range(start, stop) or range(start, stop, step)
    var start_expr: ?ast.Node = null;
    var stop_expr: ast.Node = undefined;
    var step_expr: ?ast.Node = null;

    if (args.len == 1) {
        stop_expr = args[0];
    } else if (args.len == 2) {
        start_expr = args[0];
        stop_expr = args[1];
    } else if (args.len == 3) {
        start_expr = args[0];
        stop_expr = args[1];
        step_expr = args[2];
    } else {
        return; // Invalid range() call
    }

    // Check if the loop variable is hoisted (used after the loop ends at function level)
    // Also check if it's declared in current scope (might be re-used in handler body)
    // If so, we don't wrap in block scope and use assignment instead of declaration
    const is_hoisted = self.hoisted_vars.contains(var_name);
    const is_declared = self.isDeclared(var_name);

    // Don't wrap in block scope - Python for-loop variables persist after the loop
    // The block wrapper was causing issues when the variable is used after the loop
    // within the same parent scope (e.g., inside an except handler)
    // Shadowing is handled separately via unique names

    // Determine if we need signed type (start or stop can be negative)
    // Check if start value is a negative literal
    const needs_signed = blk: {
        if (start_expr) |start| {
            // Check for negative unary expression: -(value)
            if (start == .unaryop and start.unaryop.op == .USub) {
                break :blk true;
            }
            // Check for negative constant
            if (start == .constant and start.constant.value == .int) {
                if (start.constant.value.int < 0) {
                    break :blk true;
                }
            }
        }
        // Check stop value too
        if (stop_expr == .unaryop and stop_expr.unaryop.op == .USub) {
            break :blk true;
        }
        if (stop_expr == .constant and stop_expr.constant.value == .int) {
            if (stop_expr.constant.value.int < 0) {
                break :blk true;
            }
        }
        break :blk false;
    };

    // Use i64 for signed, isize for unsigned (compatible with len operations)
    const loop_type = if (needs_signed) "i64" else "isize";

    // Check if loop variable would shadow an outer scope variable, module-level function, or imported module
    // If so, use a unique name to avoid Zig shadowing errors
    const shadows_outer = self.isDeclared(var_name) or self.module_level_funcs.contains(var_name) or self.imported_modules.contains(var_name);
    var loop_var_name = var_name;
    if (shadows_outer) {
        const unique_name = try std.fmt.allocPrint(self.allocator, "__loop_{s}_{d}", .{ var_name, self.lambda_counter });
        self.lambda_counter += 1;
        try self.var_renames.put(var_name, unique_name);
        loop_var_name = unique_name;
    }

    // Generate initialization
    // If hoisted or already declared AND NOT shadowing (using same name), assign
    // If shadowing (renamed), always declare the new unique variable
    // Otherwise, declare a new variable
    try self.emitIndent();
    if ((is_hoisted or is_declared) and !shadows_outer) {
        // Variable already exists with same name - assign with cast to match the existing type
        try self.emit(loop_var_name);
        try self.emit(" = @as(@TypeOf(");
        try self.emit(loop_var_name);
        try self.emit("), @intCast(");
        if (start_expr) |start| {
            try self.genExpr(start);
        } else {
            try self.emit("0");
        }
        try self.emit("));\n");
    } else {
        // Declare new variable (either first use, or renamed to avoid shadowing)
        try self.emit("var ");
        try self.emit(loop_var_name);
        try self.emit(": ");
        try self.emit(loop_type);
        try self.emit(" = ");
        if (start_expr) |start| {
            try self.genExpr(start);
        } else {
            try self.emit("0");
        }
        try self.emit(";\n");
        // Register the variable as declared so subsequent for loops with the same
        // variable name reuse it instead of redeclaring
        if (!shadows_outer) {
            try self.declareVar(var_name);
        }
    }

    // Generate while loop
    // Check if stop expression would generate PyValue (e.g., uncertain operands)
    // If so, extract the integer value for comparison with the isize loop variable
    // Note: type inference might say "int" but codegen can still produce PyValue
    // if the expression contains uncertain operands (e.g., external module attributes)
    const stop_is_pyvalue = blk: {
        const stop_type = self.type_inferrer.inferExpr(stop_expr) catch null;
        if (stop_type) |st| {
            if (st == .pyvalue or st == .unknown) break :blk true;
        }
        // Also check if the expression is a BinOp with uncertain operands
        // (type inference returns "int" but codegen generates PyValue)
        if (stop_expr == .binop) {
            const binop = stop_expr.binop;
            // Check if either operand is attribute access (external module constants are uncertain)
            if (binop.left.* == .attribute) break :blk true;
            if (binop.right.* == .attribute) break :blk true;
            // Check if either operand is uncertain via type inference
            const left_type = self.type_inferrer.inferExpr(binop.left.*) catch null;
            if (left_type) |lt| {
                if (lt == .pyvalue or lt == .unknown) break :blk true;
            }
            const right_type = self.type_inferrer.inferExpr(binop.right.*) catch null;
            if (right_type) |rt| {
                if (rt == .pyvalue or rt == .unknown) break :blk true;
            }
        }
        break :blk false;
    };

    try self.emitIndent();
    try self.emit("while (");
    try self.emit(loop_var_name);
    try self.emit(" < ");
    if (stop_is_pyvalue) {
        // Extract integer from PyValue for loop comparison
        try self.emit("(");
        try self.genExpr(stop_expr);
        try self.emit(").asInt()");
    } else {
        try self.genExpr(stop_expr);
    }
    try self.emit(") {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // If we shadowed an outer variable, assign loop value to outer var at the START of each iteration
    // This implements Python semantics where `for x in range(3): ...` leaves x as the last value assigned
    if (shadows_outer) {
        try self.emitIndent();
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        try self.emit(" = @as(@TypeOf(");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        try self.emit("), @intCast(");
        try self.emit(loop_var_name);
        try self.emit("));\n");
    }

    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Increment - use renamed var if shadowed
    const incr_var_name = self.var_renames.get(var_name) orelse var_name;
    try self.emitIndent();
    try self.emit(incr_var_name);
    try self.emit(" += ");
    if (step_expr) |step| {
        try self.genExpr(step);
    } else {
        try self.emit("1");
    }
    try self.emit(";\n");

    // Pop scope when exiting loop - also remove rename so it doesn't leak
    if (shadows_outer) {
        _ = self.var_renames.swapRemove(var_name);
    }
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // No block scope to close - we removed the wrapper to allow loop variable
    // to persist after the loop (Python semantics)
}

/// Generate async for loop
/// Async for loops iterate over async iterators using __aiter__() and __anext__()
/// Python: async for item in async_iterator: ...
/// Zig: while (await async_iterator.__anext__()) |item| { ... }
fn genAsyncFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
    // Set scope for this loop
    const saved_scope_id = self.current_scope_id;
    self.current_scope_id = @intFromPtr(for_stmt.body.ptr);
    defer self.current_scope_id = saved_scope_id;

    // Get the loop variable name
    if (for_stmt.target.* != .name) {
        // Async for with tuple unpacking requires special handling
        try self.emitIndent();
        try self.emit("@compileError(\"Async for with tuple unpacking not yet supported\");\n");
        return;
    }
    const var_name = sanitizeVarName(for_stmt.target.name.id);

    // Generate unique ID for this async loop
    var em_async = self.exprEmitter();
    const loop_id = em_async.reserveLabelId();

    // Emit: { const __aiter_N = <iter>.__aiter__();
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __aiter_{d} = ", .{loop_id});
    try self.genExpr(for_stmt.iter.*);
    try self.emit(".__aiter__();\n");

    // Emit: while (true) {
    try self.emitIndent();
    try self.emit("while (true) {\n");
    self.indent();
    try self.pushScope();

    // Emit: const item = __aiter_N.__anext__() catch |err| switch (err) {
    //           error.StopAsyncIteration => break,
    //           else => return err,
    //       };
    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
    try self.output.writer(self.allocator).print(" = __aiter_{d}.__anext__() catch |err| switch (err) {{\n", .{loop_id});
    self.indent();

    try self.emitIndent();
    try self.emit("error.StopAsyncIteration => break,\n");

    try self.emitIndent();
    try self.emit("else => return err,\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Declare the variable for type inference
    try self.declareVar(var_name);

    // Generate body statements
    for (for_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.popScope();
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n"); // end while

    // Handle optional else clause (runs if loop completes without break)
    if (for_stmt.orelse_body) |else_body| {
        try self.emitIndent();
        try self.emit("// for/else: else body runs if loop completed normally\n");
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n"); // end block
}

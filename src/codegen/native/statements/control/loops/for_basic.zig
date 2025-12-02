/// For loop code generation (basic, range, tuple unpacking)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const for_special = @import("for_special.zig");
const genEnumerateLoop = for_special.genEnumerateLoop;
const genZipLoop = for_special.genZipLoop;
const zig_keywords = @import("zig_keywords");
const producesBlockExpression = @import("../../../expressions.zig").producesBlockExpression;

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
                    .expr => |e| if (exprUsesVar(e.*, var_name)) break :blk true,
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
        else => false,
    };
}

/// Check if a variable is used in the loop body
fn varUsedInBody(body: []ast.Node, var_name: []const u8) bool {
    for (body) |stmt| {
        if (stmtUsesVar(stmt, var_name)) return true;
    }
    return false;
}

/// Generate tuple unpacking for loop (e.g., for k, v in items)
fn genTupleUnpackLoop(self: *NativeCodegen, target: ast.Node, iter: ast.Node, body: []ast.Node) CodegenError!void {
    // Get target elements from either list or tuple
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => @panic("Tuple unpacking requires list or tuple target"),
    };
    if (target_elts.len == 0) {
        @panic("Tuple unpacking requires at least one variable");
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

    // If there's nested unpacking, emit a comment and use simpler approach
    if (has_nested) {
        try self.emitIndent();
        try self.emit("// TODO: Nested tuple unpacking not fully supported\n");
    }

    // Generate for loop over iterable
    try self.emitIndent();
    try self.emit("for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iter);

    // Check if this is a method call like dict.items()
    const is_method_call = iter == .call and iter.call.func.* == .attribute;

    // If iterating over list (including method calls that return lists), add .items
    if (iter_type == .list) {
        if (is_method_call) {
            // Method call returns ArrayList - wrap in parens for .items
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else if (iter == .list) {
            // Inline list literal
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else {
            // Variable that holds ArrayList
            try self.genExpr(iter);
            try self.emit(".items");
        }
    } else {
        // Not a list type - iterate directly
        try self.genExpr(iter);
    }

    // Use unique temp variable for tuple
    const unique_id = self.output.items.len;
    try self.output.writer(self.allocator).print(") |__tuple_{d}__| {{\n", .{unique_id});

    self.indent();
    try self.pushScope();

    // Unpack tuple elements using struct field access: const x = __tuple__.@"0"; const y = __tuple__.@"1";
    // Escape variable names if they're Zig keywords (e.g., "fn" -> @"fn")
    // Handle Python's discard pattern: `for _, v in items:` - use `_ = value;` to discard
    for (var_names, 0..) |var_name, i| {
        try self.emitIndent();
        if (std.mem.eql(u8, var_name, "_")) {
            // Discard pattern - explicitly discard the value
            try self.output.writer(self.allocator).print("_ = __tuple_{d}__.@\"{d}\";\n", .{ unique_id, i });
        } else {
            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.output.writer(self.allocator).print(" = __tuple_{d}__.@\"{d}\";\n", .{ unique_id, i });
        }
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate for loop
pub fn genFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
    // Set scope ID for scope-aware mutation tracking
    // Each loop body is a unique scope (using pointer address)
    const saved_scope_id = self.current_scope_id;
    self.current_scope_id = @intFromPtr(for_stmt.body.ptr);
    defer self.current_scope_id = saved_scope_id;

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
        // Unsupported target type - emit error comment
        try self.emitIndent();
        try self.emit("// TODO: Unsupported for loop target type\n");
        return;
    }
    const var_name = sanitizeVarName(for_stmt.target.name.id);

    // Check iter type first (needed for tuple special case)
    const iter_type = try self.type_inferrer.inferExpr(for_stmt.iter.*);

    // Check if variable is used in body once (used for all patterns below)
    const tuple_var_used = varUsedInBody(for_stmt.body, for_stmt.target.name.id);

    // Special case: tuple iteration requires inline for (comptime)
    if (iter_type == .tuple) {
        try self.emitIndent();
        try self.emit("inline for (");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(") |");
        if (!tuple_var_used) {
            try self.emit("_");
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        }
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

        // Register loop variable type as widened tuple element type
        // This allows type inference inside the loop body to know f's type
        if (iter_type.tuple.len > 0) {
            var elem_type = iter_type.tuple[0];
            for (iter_type.tuple[1..]) |t| {
                elem_type = elem_type.widen(t);
            }
            try self.type_inferrer.putScopedVar(for_stmt.target.name.id, elem_type);

            // If any tuple element is a callable type, register loop variable as callable
            // This enables .call() syntax for calls like pow_op(a, b) -> pow_op.call(a, b)
            // where the tuple is (pow, operator.pow) - both callable structs
            if (elem_type == .callable) {
                const owned_name = try self.allocator.dupe(u8, var_name);
                try self.callable_vars.put(owned_name, {});
            }
        }

        // Check if iterating over tuple containing callable builtin references
        // e.g., for pow_op in pow, operator.pow:
        // Both pow and operator.pow are callable structs, need .call() syntax
        if (for_stmt.iter.* == .tuple) {
            const tuple_elts = for_stmt.iter.tuple.elts;
            for (tuple_elts) |elt| {
                // Check for builtin references: pow, operator.pow, etc.
                if (elt == .name) {
                    const name = elt.name.id;
                    if (std.mem.eql(u8, name, "pow")) {
                        // Loop variable iterates over callable structs
                        const owned_name = try self.allocator.dupe(u8, var_name);
                        try self.callable_vars.put(owned_name, {});
                        break;
                    }
                } else if (elt == .attribute) {
                    const attr = elt.attribute;
                    if (attr.value.* == .name) {
                        const mod_name = attr.value.name.id;
                        if (std.mem.eql(u8, mod_name, "operator")) {
                            if (std.mem.eql(u8, attr.attr, "pow") or std.mem.eql(u8, attr.attr, "mod")) {
                                // Loop variable iterates over callable structs
                                const owned_name = try self.allocator.dupe(u8, var_name);
                                try self.callable_vars.put(owned_name, {});
                                break;
                            }
                        }
                    }
                }
            }
        }

        // If variable appears used in AST but might not be used in generated code
        // (e.g., isinstance(x, T) becomes compile-time true), add a reference to avoid
        // "unused capture" error. Use @TypeOf() as it doesn't require runtime evaluation.
        if (tuple_var_used) {
            try self.emitIndent();
            try self.emit("_ = @TypeOf(");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
            try self.emit(");\n");
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

    // Regular iteration over collection
    try self.emitIndent();

    // Handle dict iteration - iterate over .keys()
    if (iter_type == .dict) {
        try self.emit("for (");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(".keys()) |");
        if (!tuple_var_used) {
            try self.emit("_");
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        }
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

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
        try self.type_inferrer.var_types.put(var_name, .{ .string = .runtime });

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

        self.popScope();
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
    } else if (iter_type == .list and for_stmt.iter.* == .list) {
        // Inline ArrayList literal - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else if (iter_type == .list and for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
        // Method call that returns ArrayList - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else if ((iter_type == .list or iter_type == .deque) and for_stmt.iter.* == .call) {
        // Function call that returns ArrayList (like chain(a, b)) - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else {
        // ArrayList (list or deque types) need .items for iteration
        // Block expressions (listcomp, etc.) need to be wrapped in a temp variable
        if (iter_type == .list or iter_type == .deque) {
            if (producesBlockExpression(for_stmt.iter.*)) {
                // Wrap block expression: blk: { const __iter = <expr>; break :blk __iter.items; }
                try self.emit("blk: { const __iter = ");
                try self.genExpr(for_stmt.iter.*);
                try self.emit("; break :blk __iter.items; }");
            } else {
                try self.genExpr(for_stmt.iter.*);
                try self.emit(".items");
            }
        } else {
            try self.genExpr(for_stmt.iter.*);
        }
    }

    // Check if variable is used in body - if not, use _ to avoid unused capture error
    const var_used = varUsedInBody(for_stmt.body, for_stmt.target.name.id);
    try self.emit(") |");
    if (!var_used) {
        // Use bare _ for unused capture (Zig requires this)
        try self.emit("_");
    } else {
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
    }
    try self.emit("| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

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
    if (for_stmt.iter.* == .name) {
        const iter_var_name = for_stmt.iter.name.id;
        if (self.vararg_params.contains(iter_var_name)) {
            // Register loop variable as i64 type
            try self.type_inferrer.var_types.put(var_name, .{ .int = .bounded });
        }
    }

    // If iterating over a deque (ArrayList from itertools, etc.), loop variable is i64
    if (iter_type == .deque) {
        try self.type_inferrer.var_types.put(var_name, .{ .int = .bounded });
    }

    // If iterating over a list of callables (PyCallable), register loop var as callable
    // This enables .call() syntax for calls like f(arg) -> f.call(arg)
    // Also register in var_types for type inference of call return values
    if (@as(std.meta.Tag(@TypeOf(iter_type)), iter_type) == .list) {
        if (@as(std.meta.Tag(@TypeOf(iter_type.list.*)), iter_type.list.*) == .callable) {
            // Register loop variable as callable for .call() generation
            const owned_name = try self.allocator.dupe(u8, var_name);
            try self.callable_vars.put(owned_name, {});
            // Register in var_types for type inference (callable call returns string/bytes)
            try self.type_inferrer.var_types.put(var_name, .callable);
        }
    }

    for (for_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Clean up loop capture tracking and renames when exiting loop
    _ = self.loop_capture_vars.swapRemove(var_name);
    _ = self.var_renames.swapRemove(var_name);

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

    // Wrap range loop in block scope to prevent variable shadowing
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

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

    // Generate initialization (always declare as new variable in block scope)
    try self.emitIndent();
    try self.emit("var ");
    try self.emit(var_name);
    try self.emit(": ");
    try self.emit(loop_type);
    try self.emit(" = ");
    if (start_expr) |start| {
        try self.genExpr(start);
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");

    // Generate while loop
    try self.emitIndent();
    try self.emit("while (");
    try self.emit(var_name);
    try self.emit(" < ");
    try self.genExpr(stop_expr);
    try self.emit(") {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Increment
    try self.emitIndent();
    try self.emit(var_name);
    try self.emit(" += ");
    if (step_expr) |step| {
        try self.genExpr(step);
    } else {
        try self.emit("1");
    }
    try self.emit(";\n");

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

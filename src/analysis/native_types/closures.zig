/// Closure analysis - detect captured variables in nested functions
const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const ast = @import("ast");

/// Collect variable names from an assignment target (handles name, tuple, list)
fn collectTargetVars(node: ast.Node, vars: *hashmap_helper.StringHashMap(void)) !void {
    switch (node) {
        .name => |n| {
            try vars.put(n.id, {});
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try collectTargetVars(elt, vars);
            }
        },
        .list => |l| {
            for (l.elts) |elt| {
                try collectTargetVars(elt, vars);
            }
        },
        .starred => |s| {
            try collectTargetVars(s.value.*, vars);
        },
        else => {}, // Ignore attribute, subscript, etc.
    }
}

/// Find all variables used in an expression
fn findUsedVars(node: ast.Node, vars: *hashmap_helper.StringHashMap(void), allocator: std.mem.Allocator) !void {
    switch (node) {
        .name => |n| {
            try vars.put(n.id, {});
        },
        .binop => |b| {
            try findUsedVars(b.left.*, vars, allocator);
            try findUsedVars(b.right.*, vars, allocator);
        },
        .unaryop => |u| {
            try findUsedVars(u.operand.*, vars, allocator);
        },
        .compare => |c| {
            try findUsedVars(c.left.*, vars, allocator);
            for (c.comparators) |comp| {
                try findUsedVars(comp, vars, allocator);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try findUsedVars(val, vars, allocator);
            }
        },
        .call => |c| {
            // Include self in used vars for self.method() calls
            // Nested functions need to capture 'self' to call methods on it
            try findUsedVars(c.func.*, vars, allocator);
            // Check arguments too
            for (c.args) |arg| {
                try findUsedVars(arg, vars, allocator);
            }
        },
        .subscript => |s| {
            try findUsedVars(s.value.*, vars, allocator);
            switch (s.slice) {
                .index => |idx| try findUsedVars(idx.*, vars, allocator),
                .slice => |slice_range| {
                    if (slice_range.lower) |lower| try findUsedVars(lower.*, vars, allocator);
                    if (slice_range.upper) |upper| try findUsedVars(upper.*, vars, allocator);
                    if (slice_range.step) |step| try findUsedVars(step.*, vars, allocator);
                },
            }
        },
        .attribute => |a| {
            try findUsedVars(a.value.*, vars, allocator);
        },
        .list => |l| {
            for (l.elts) |elt| {
                try findUsedVars(elt, vars, allocator);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try findUsedVars(key, vars, allocator);
            }
            for (d.values) |val| {
                try findUsedVars(val, vars, allocator);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try findUsedVars(elt, vars, allocator);
            }
        },
        .fstring => |f| {
            for (f.parts) |part| {
                switch (part) {
                    .expr => |e| try findUsedVars(e.node.*, vars, allocator),
                    .format_expr => |fe| try findUsedVars(fe.expr.*, vars, allocator),
                    .conv_expr => |ce| try findUsedVars(ce.expr.*, vars, allocator),
                    .literal => {},
                }
            }
        },
        .listcomp => |lc| {
            try findUsedVars(lc.elt.*, vars, allocator);
            for (lc.generators) |gen| {
                try findUsedVars(gen.iter.*, vars, allocator);
            }
        },
        .dictcomp => |dc| {
            try findUsedVars(dc.key.*, vars, allocator);
            try findUsedVars(dc.value.*, vars, allocator);
            for (dc.generators) |gen| {
                try findUsedVars(gen.iter.*, vars, allocator);
            }
        },
        else => {},
    }
}

/// Find all variables used in a statement
fn findUsedVarsInStmt(node: ast.Node, vars: *hashmap_helper.StringHashMap(void), allocator: std.mem.Allocator) !void {
    switch (node) {
        .assign => |a| {
            try findUsedVars(a.value.*, vars, allocator);
        },
        .ann_assign => |a| {
            if (a.value) |val| {
                try findUsedVars(val.*, vars, allocator);
            }
        },
        .aug_assign => |a| {
            try findUsedVars(a.target.*, vars, allocator);
            try findUsedVars(a.value.*, vars, allocator);
        },
        .expr_stmt => |e| {
            try findUsedVars(e.value.*, vars, allocator);
        },
        .return_stmt => |r| {
            if (r.value) |val| {
                try findUsedVars(val.*, vars, allocator);
            }
        },
        .if_stmt => |i| {
            try findUsedVars(i.condition.*, vars, allocator);
            for (i.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
            for (i.else_body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        .for_stmt => |f| {
            try findUsedVars(f.iter.*, vars, allocator);
            for (f.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        .while_stmt => |w| {
            try findUsedVars(w.condition.*, vars, allocator);
            for (w.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        .function_def => |f| {
            for (f.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        .assert_stmt => |a| {
            try findUsedVars(a.condition.*, vars, allocator);
            if (a.msg) |msg| {
                try findUsedVars(msg.*, vars, allocator);
            }
        },
        .try_stmt => |t| {
            for (t.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
            for (t.handlers) |handler| {
                for (handler.body) |stmt| {
                    try findUsedVarsInStmt(stmt, vars, allocator);
                }
            }
            for (t.finalbody) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        .class_def => |c| {
            // Nested class methods may use variables from outer scope
            for (c.body) |stmt| {
                try findUsedVarsInStmt(stmt, vars, allocator);
            }
        },
        else => {},
    }
}

/// Find all locally defined variables in a function
fn findLocalVars(func: ast.Node.FunctionDef, vars: *hashmap_helper.StringHashMap(void), _: std.mem.Allocator) !void {
    // Add function parameters
    for (func.args) |arg| {
        try vars.put(arg.name, {});
    }
    // Add vararg (*args) parameter if present
    if (func.vararg) |vararg_name| {
        try vars.put(vararg_name, {});
    }
    // Add kwarg (**kwargs) parameter if present
    if (func.kwarg) |kwarg_name| {
        try vars.put(kwarg_name, {});
    }

    // Find all assignments recursively in function body
    try findLocalVarsInStmts(func.body, vars);
}

/// Recursively find local variable assignments in statements
fn findLocalVarsInStmts(stmts: []ast.Node, vars: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    for (stmts) |stmt| {
        try findLocalVarsInStmt(stmt, vars);
    }
}

/// Find local variable assignments in a single statement (recursive)
fn findLocalVarsInStmt(stmt: ast.Node, vars: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    switch (stmt) {
        .assign => |a| {
            for (a.targets) |target| {
                if (target == .name) {
                    try vars.put(target.name.id, {});
                }
            }
        },
        .ann_assign => |a| {
            if (a.target.* == .name) {
                try vars.put(a.target.name.id, {});
            }
        },
        .for_stmt => |f| {
            // For loop target is a local variable
            if (f.target.* == .name) {
                try vars.put(f.target.name.id, {});
            }
            // Recurse into for loop body
            try findLocalVarsInStmts(f.body, vars);
            if (f.orelse_body) |orelse_body| {
                try findLocalVarsInStmts(orelse_body, vars);
            }
        },
        .while_stmt => |w| {
            // Recurse into while loop body
            try findLocalVarsInStmts(w.body, vars);
            if (w.orelse_body) |orelse_body| {
                try findLocalVarsInStmts(orelse_body, vars);
            }
        },
        .if_stmt => |i| {
            // Recurse into if/else bodies
            try findLocalVarsInStmts(i.body, vars);
            try findLocalVarsInStmts(i.else_body, vars);
        },
        .try_stmt => |t| {
            // Recurse into try/except/finally bodies
            try findLocalVarsInStmts(t.body, vars);
            for (t.handlers) |handler| {
                if (handler.name) |name| {
                    try vars.put(name, {});
                }
                try findLocalVarsInStmts(handler.body, vars);
            }
            try findLocalVarsInStmts(t.else_body, vars);
            try findLocalVarsInStmts(t.finalbody, vars);
        },
        .with_stmt => |w| {
            // With statement may bind to a name or tuple (as target)
            if (w.optional_vars) |target| {
                try collectTargetVars(target.*, vars);
            }
            try findLocalVarsInStmts(w.body, vars);
        },
        .function_def => |f| {
            // Nested function name is a local variable
            try vars.put(f.name, {});
            // Don't recurse - nested function has its own scope
        },
        .class_def => |c| {
            // Nested class name is a local variable
            try vars.put(c.name, {});
            // Don't recurse - nested class has its own scope
        },
        else => {},
    }
}

/// Analyze a nested function to find captured variables
pub fn analyzeClosure(
    func: ast.Node.FunctionDef,
    parent_locals: hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) ![][]const u8 {
    var used = hashmap_helper.StringHashMap(void).init(allocator);
    defer used.deinit();

    var local = hashmap_helper.StringHashMap(void).init(allocator);
    defer local.deinit();

    // Find all used variables
    for (func.body) |stmt| {
        try findUsedVarsInStmt(stmt, &used, allocator);
    }

    // Find all local variables
    try findLocalVars(func, &local, allocator);

    // Captured vars = used - local, intersected with parent_locals
    var captures = std.ArrayList([]const u8){};
    for (used.keys()) |var_name| {
        if (!local.contains(var_name) and parent_locals.contains(var_name)) {
            try captures.append(allocator, var_name);
        }
    }

    return captures.toOwnedSlice(allocator);
}

/// Recursively analyze nested functions and populate captured_vars
pub fn analyzeNestedFunctions(
    stmts: []ast.Node,
    parent_locals: ?hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) !void {
    for (stmts) |*stmt| {
        if (stmt.* == .function_def) {
            var func = &stmt.function_def;

            if (func.is_nested and parent_locals != null) {
                // Analyze captures
                func.captured_vars = try analyzeClosure(func.*, parent_locals.?, allocator);
            }

            // Build local var set for this function (includes parent scope)
            var locals = hashmap_helper.StringHashMap(void).init(allocator);
            defer locals.deinit();

            // Include parent locals so nested closures can capture from grandparent scopes
            if (parent_locals) |pl| {
                for (pl.keys()) |key| {
                    try locals.put(key, {});
                }
            }

            // Add this function's own locals
            try findLocalVars(func.*, &locals, allocator);

            // Recursively analyze nested functions in body
            try analyzeNestedFunctions(func.body, locals, allocator);
        } else if (stmt.* == .if_stmt) {
            try analyzeNestedFunctions(stmt.if_stmt.body, parent_locals, allocator);
            try analyzeNestedFunctions(stmt.if_stmt.else_body, parent_locals, allocator);
        } else if (stmt.* == .for_stmt) {
            try analyzeNestedFunctions(stmt.for_stmt.body, parent_locals, allocator);
        } else if (stmt.* == .while_stmt) {
            try analyzeNestedFunctions(stmt.while_stmt.body, parent_locals, allocator);
        } else if (stmt.* == .try_stmt) {
            try analyzeNestedFunctions(stmt.try_stmt.body, parent_locals, allocator);
            for (stmt.try_stmt.handlers) |handler| {
                try analyzeNestedFunctions(handler.body, parent_locals, allocator);
            }
            try analyzeNestedFunctions(stmt.try_stmt.finalbody, parent_locals, allocator);
        } else if (stmt.* == .class_def) {
            // Analyze nested functions inside class methods
            try analyzeNestedFunctions(stmt.class_def.body, parent_locals, allocator);
        }
    }
}

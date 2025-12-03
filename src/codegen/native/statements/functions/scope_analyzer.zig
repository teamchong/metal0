/// Scope Escape Analyzer
///
/// Analyzes function bodies to find variables that are:
/// 1. Declared inside inner scopes (with, try, if, for blocks)
/// 2. Used outside that scope (Python allows this, Zig doesn't)
///
/// These variables need to be hoisted to function scope.
/// We record the initializer expression so we can use @TypeOf(expr) for type inference.
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");

/// Common error type for scope analysis functions (to break recursive error set inference)
pub const ScopeAnalysisError = std.mem.Allocator.Error;

/// Source: what kind of block declared the escaped var
pub const EscapedSource = enum { with_stmt, try_except, for_loop, if_stmt };

/// Variable that needs hoisting due to scope escape
pub const EscapedVar = struct {
    name: []const u8,
    /// The AST node of the initializer expression (for @TypeOf)
    /// null if we can't determine (fall back to anytype or i64)
    init_expr: ?*const ast.Node,
    /// Source: what kind of block declared this var
    source: EscapedSource,
};

/// Result of scope analysis
pub const ScopeAnalysis = struct {
    /// Variables that escape their declaring scope
    escaped_vars: std.ArrayList(EscapedVar),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ScopeAnalysis) void {
        self.escaped_vars.deinit(self.allocator);
    }
};

/// Analyze a function body for scope-escaping variables
pub fn analyzeScopes(body: []const ast.Node, allocator: std.mem.Allocator) !ScopeAnalysis {
    var result = ScopeAnalysis{
        .escaped_vars = std.ArrayList(EscapedVar){},
        .allocator = allocator,
    };
    errdefer result.escaped_vars.deinit(allocator);

    // Track variables declared at each scope level
    var declared_in_inner = hashmap_helper.StringHashMap(EscapedVar).init(allocator);
    defer declared_in_inner.deinit();

    // Track all variable uses at function level
    var used_at_outer = hashmap_helper.StringHashMap(void).init(allocator);
    defer used_at_outer.deinit();

    // First pass: collect variables declared in inner scopes
    for (body) |stmt| {
        try collectInnerScopeDecls(&declared_in_inner, stmt, allocator);
    }

    // Second pass: collect variable uses at outer level
    for (body) |stmt| {
        try collectOuterUses(&used_at_outer, stmt, allocator);
    }

    // Third pass: detect cross-loop escapes (var declared in for-loop A, used in for-loop B)
    try detectCrossLoopEscapes(body, &declared_in_inner, &used_at_outer, allocator);

    // Find variables that are declared inner but used outer
    var iter = declared_in_inner.iterator();
    while (iter.next()) |entry| {
        if (used_at_outer.contains(entry.key_ptr.*)) {
            try result.escaped_vars.append(allocator, entry.value_ptr.*);
        }
    }

    return result;
}

/// Detect variables that escape across sibling for-loops
/// e.g., dsize defined in for-loop at index 0, used in for-loop at index 1
fn detectCrossLoopEscapes(
    body: []const ast.Node,
    declared: *hashmap_helper.StringHashMap(EscapedVar),
    used_at_outer: *hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) !void {
    // Track which variables are declared in which for-loop by index
    var loop_decls = std.ArrayList(struct { idx: usize, vars: hashmap_helper.StringHashMap(void) }){};
    defer {
        for (loop_decls.items) |*item| {
            item.vars.deinit();
        }
        loop_decls.deinit(allocator);
    }

    // Collect for-loop declarations with their index
    for (body, 0..) |stmt, idx| {
        if (stmt == .for_stmt) {
            var vars = hashmap_helper.StringHashMap(void).init(allocator);
            try collectForLoopDecls(&vars, stmt.for_stmt, allocator);
            try loop_decls.append(allocator, .{ .idx = idx, .vars = vars });
        }
    }

    // For each for-loop, check if its vars are used in later for-loops
    for (loop_decls.items) |decl_loop| {
        var var_iter = decl_loop.vars.iterator();
        while (var_iter.next()) |var_entry| {
            const var_name = var_entry.key_ptr.*;
            // Check if used in ANY for-loop after this one
            for (body[decl_loop.idx + 1 ..]) |stmt| {
                if (stmt == .for_stmt) {
                    const later_for = stmt.for_stmt;
                    // Skip if the later for-loop declares the same variable as its target
                    // In Python, `for b in ...: for b in ...:` means each loop has its own `b`
                    // The second `for b` shadows the first, not uses it
                    const later_target_name = if (later_for.target.* == .name) later_for.target.name.id else null;
                    if (later_target_name != null and std.mem.eql(u8, later_target_name.?, var_name)) {
                        continue; // Not an escape - later loop re-declares this variable
                    }

                    var uses = hashmap_helper.StringHashMap(void).init(allocator);
                    defer uses.deinit();
                    try collectAllVarRefsInForLoop(&uses, later_for, allocator);
                    if (uses.contains(var_name)) {
                        // Variable escapes! Mark it as used at outer level
                        try used_at_outer.put(var_name, {});
                        // Make sure it's in declared_in_inner too
                        if (!declared.contains(var_name)) {
                            try declared.put(var_name, .{
                                .name = var_name,
                                .init_expr = null,
                                .source = .for_loop,
                            });
                        }
                        break;
                    }
                }
            }
        }
    }
}

/// Collect all variables declared in a for-loop (loop var + assignments in body)
fn collectForLoopDecls(
    vars: *hashmap_helper.StringHashMap(void),
    for_stmt: ast.Node.For,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    // Loop target variable
    if (for_stmt.target.* == .name) {
        try vars.put(for_stmt.target.name.id, {});
    } else if (for_stmt.target.* == .tuple) {
        for (for_stmt.target.tuple.elts) |elt| {
            if (elt == .name) {
                try vars.put(elt.name.id, {});
            }
        }
    }
    // Assignments in body
    for (for_stmt.body) |stmt| {
        try collectAssignmentsInStmt(vars, stmt, allocator);
    }
}

/// Collect assignments in a statement (recursive for nested loops/ifs)
fn collectAssignmentsInStmt(
    vars: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    switch (node) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (target == .name) {
                    try vars.put(target.name.id, {});
                }
            }
        },
        .for_stmt => |for_s| {
            try collectForLoopDecls(vars, for_s, allocator);
        },
        .if_stmt => |if_s| {
            for (if_s.body) |stmt| {
                try collectAssignmentsInStmt(vars, stmt, allocator);
            }
            for (if_s.else_body) |stmt| {
                try collectAssignmentsInStmt(vars, stmt, allocator);
            }
        },
        else => {},
    }
}

/// Collect all variable references in a for-loop (recursive)
/// Excludes variables declared by nested for-loops (they shadow, not use)
fn collectAllVarRefsInForLoop(
    uses: *hashmap_helper.StringHashMap(void),
    for_stmt: ast.Node.For,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    // First, collect variables declared by nested for-loops (to exclude them)
    var nested_decls = hashmap_helper.StringHashMap(void).init(allocator);
    defer nested_decls.deinit();
    try collectNestedForLoopTargets(&nested_decls, for_stmt.body, allocator);

    // Iterator expression (doesn't contain declarations)
    try collectVarRefs(uses, for_stmt.iter.*, allocator);
    // Body statements
    for (for_stmt.body) |stmt| {
        try collectAllVarRefsInStmtExcluding(uses, stmt, &nested_decls, allocator);
    }

    // Remove any nested declarations from uses (they shadow, not reference)
    var decl_iter = nested_decls.iterator();
    while (decl_iter.next()) |entry| {
        _ = uses.swapRemove(entry.key_ptr.*);
    }
}

/// Collect for-loop target variables from nested for-loops in a body
fn collectNestedForLoopTargets(
    decls: *hashmap_helper.StringHashMap(void),
    body: []const ast.Node,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    for (body) |stmt| {
        switch (stmt) {
            .for_stmt => |for_s| {
                // Add this for-loop's target
                if (for_s.target.* == .name) {
                    try decls.put(for_s.target.name.id, {});
                }
                // Recurse into body for deeper nested for-loops
                try collectNestedForLoopTargets(decls, for_s.body, allocator);
            },
            .if_stmt => |if_s| {
                try collectNestedForLoopTargets(decls, if_s.body, allocator);
                try collectNestedForLoopTargets(decls, if_s.else_body, allocator);
            },
            .while_stmt => |while_s| {
                try collectNestedForLoopTargets(decls, while_s.body, allocator);
            },
            else => {},
        }
    }
}

/// Collect variable references, excluding variables in the exclude set
fn collectAllVarRefsInStmtExcluding(
    uses: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    exclude: *const hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    switch (node) {
        .assign => |assign| {
            try collectVarRefsExcluding(uses, assign.value.*, exclude, allocator);
        },
        .expr_stmt => |expr| {
            try collectVarRefsExcluding(uses, expr.value.*, exclude, allocator);
        },
        .for_stmt => |for_s| {
            // Recurse but the nested targets are already in exclude
            try collectVarRefsExcluding(uses, for_s.iter.*, exclude, allocator);
            for (for_s.body) |stmt| {
                try collectAllVarRefsInStmtExcluding(uses, stmt, exclude, allocator);
            }
        },
        .if_stmt => |if_s| {
            try collectVarRefsExcluding(uses, if_s.condition.*, exclude, allocator);
            for (if_s.body) |stmt| {
                try collectAllVarRefsInStmtExcluding(uses, stmt, exclude, allocator);
            }
            for (if_s.else_body) |stmt| {
                try collectAllVarRefsInStmtExcluding(uses, stmt, exclude, allocator);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectVarRefsExcluding(uses, val.*, exclude, allocator);
            }
        },
        else => {},
    }
}

/// Like collectVarRefs but skips variables in exclude set
fn collectVarRefsExcluding(
    uses: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    exclude: *const hashmap_helper.StringHashMap(void),
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    switch (node) {
        .name => |n| {
            if (!exclude.contains(n.id)) {
                try uses.put(n.id, {});
            }
        },
        .binop => |b| {
            try collectVarRefsExcluding(uses, b.left.*, exclude, allocator);
            try collectVarRefsExcluding(uses, b.right.*, exclude, allocator);
        },
        .unaryop => |u| {
            try collectVarRefsExcluding(uses, u.operand.*, exclude, allocator);
        },
        .call => |c| {
            try collectVarRefsExcluding(uses, c.func.*, exclude, allocator);
            for (c.args) |arg| {
                try collectVarRefsExcluding(uses, arg, exclude, allocator);
            }
        },
        .attribute => |a| {
            try collectVarRefsExcluding(uses, a.value.*, exclude, allocator);
        },
        .subscript => |s| {
            try collectVarRefsExcluding(uses, s.value.*, exclude, allocator);
        },
        .compare => |cmp| {
            try collectVarRefsExcluding(uses, cmp.left.*, exclude, allocator);
            for (cmp.comparators) |comp| {
                try collectVarRefsExcluding(uses, comp, exclude, allocator);
            }
        },
        else => {},
    }
}

/// Collect all variable references in a statement (recursive)
fn collectAllVarRefsInStmt(
    uses: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    allocator: std.mem.Allocator,
) error{OutOfMemory}!void {
    switch (node) {
        .assign => |assign| {
            try collectVarRefs(uses, assign.value.*, allocator);
        },
        .expr_stmt => |expr| {
            try collectVarRefs(uses, expr.value.*, allocator);
        },
        .for_stmt => |for_s| {
            try collectAllVarRefsInForLoop(uses, for_s, allocator);
        },
        .if_stmt => |if_s| {
            try collectVarRefs(uses, if_s.condition.*, allocator);
            for (if_s.body) |stmt| {
                try collectAllVarRefsInStmt(uses, stmt, allocator);
            }
            for (if_s.else_body) |stmt| {
                try collectAllVarRefsInStmt(uses, stmt, allocator);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectVarRefs(uses, val.*, allocator);
            }
        },
        else => {},
    }
}

/// Collect variables declared inside inner scopes (with, try, etc.)
fn collectInnerScopeDecls(
    decls: *hashmap_helper.StringHashMap(EscapedVar),
    node: ast.Node,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .with_stmt => |with| {
            // with expr as var: -> var is declared in inner scope
            if (with.optional_vars) |vars_node| {
                // Extract variable name from the target node
                if (vars_node.* == .name) {
                    const var_name = vars_node.name.id;
                    try decls.put(var_name, .{
                        .name = var_name,
                        .init_expr = with.context_expr,
                        .source = .with_stmt,
                    });
                }
            }
            // Recursively check body for more inner scopes
            for (with.body) |stmt| {
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
        },
        .try_stmt => |try_s| {
            // Variables assigned in try/except body
            for (try_s.body) |stmt| {
                try collectAssignments(decls, stmt, .try_except, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
            // except handler variable: except ValueError as e
            for (try_s.handlers) |handler| {
                if (handler.name) |exc_name| {
                    try decls.put(exc_name, .{
                        .name = exc_name,
                        .init_expr = null, // Exception type, can't use @TypeOf
                        .source = .try_except,
                    });
                }
                for (handler.body) |stmt| {
                    try collectAssignments(decls, stmt, .try_except, allocator);
                    try collectInnerScopeDecls(decls, stmt, allocator);
                }
            }
        },
        .if_stmt => |if_s| {
            for (if_s.body) |stmt| {
                try collectAssignments(decls, stmt, .if_stmt, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
            for (if_s.else_body) |stmt| {
                try collectAssignments(decls, stmt, .if_stmt, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
        },
        .for_stmt => |for_s| {
            // Loop variable
            if (for_s.target.* == .name) {
                const var_name = for_s.target.name.id;
                try decls.put(var_name, .{
                    .name = var_name,
                    .init_expr = null, // Iterator element, complex type
                    .source = .for_loop,
                });
            }
            for (for_s.body) |stmt| {
                try collectAssignments(decls, stmt, .for_loop, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
        },
        .while_stmt => |while_s| {
            for (while_s.body) |stmt| {
                try collectAssignments(decls, stmt, .if_stmt, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
        },
        else => {},
    }
}

/// Collect assignments that create new variables
fn collectAssignments(
    decls: *hashmap_helper.StringHashMap(EscapedVar),
    node: ast.Node,
    source: EscapedSource,
    _: std.mem.Allocator,
) !void {
    if (node == .assign) {
        const assign = node.assign;
        if (assign.targets.len > 0) {
            const target = assign.targets[0];
            if (target == .name) {
                const var_name = target.name.id;
                // Only add if not already declared
                if (!decls.contains(var_name)) {
                    try decls.put(var_name, .{
                        .name = var_name,
                        .init_expr = assign.value,
                        .source = source,
                    });
                }
            }
        }
    }
}

/// Collect variable uses at the outer (function) level
/// These are uses that are NOT inside inner scopes
fn collectOuterUses(
    uses: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        // Skip into inner scopes - we only want outer-level uses
        .with_stmt, .try_stmt, .if_stmt, .for_stmt, .while_stmt => {
            // Don't recurse - uses inside these don't count as "outer"
        },
        // For assignments and expressions at outer level, collect uses
        .assign => |assign| {
            // The value side uses variables
            try collectVarRefs(uses, assign.value.*, allocator);
        },
        .expr_stmt => |expr| {
            try collectVarRefs(uses, expr.value.*, allocator);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectVarRefs(uses, val.*, allocator);
            }
        },
        else => {},
    }
}

/// Recursively collect all variable name references in an expression
fn collectVarRefs(
    uses: *hashmap_helper.StringHashMap(void),
    node: ast.Node,
    allocator: std.mem.Allocator,
) !void {
    switch (node) {
        .name => |n| {
            try uses.put(n.id, {});
        },
        .call => |call| {
            try collectVarRefs(uses, call.func.*, allocator);
            for (call.args) |arg| {
                try collectVarRefs(uses, arg, allocator);
            }
        },
        .attribute => |attr| {
            try collectVarRefs(uses, attr.value.*, allocator);
        },
        .binop => |bin| {
            try collectVarRefs(uses, bin.left.*, allocator);
            try collectVarRefs(uses, bin.right.*, allocator);
        },
        .compare => |cmp| {
            try collectVarRefs(uses, cmp.left.*, allocator);
            for (cmp.comparators) |c| {
                try collectVarRefs(uses, c, allocator);
            }
        },
        .subscript => |sub| {
            try collectVarRefs(uses, sub.value.*, allocator);
            // Handle slice union - only recurse into index case
            switch (sub.slice) {
                .index => |idx| try collectVarRefs(uses, idx.*, allocator),
                .slice => |sl| {
                    if (sl.lower) |l| try collectVarRefs(uses, l.*, allocator);
                    if (sl.upper) |u| try collectVarRefs(uses, u.*, allocator);
                    if (sl.step) |s| try collectVarRefs(uses, s.*, allocator);
                },
            }
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectVarRefs(uses, elem, allocator);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectVarRefs(uses, elem, allocator);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try collectVarRefs(uses, key, allocator);
            }
            for (dict.values) |val| {
                try collectVarRefs(uses, val, allocator);
            }
        },
        .if_expr => |if_e| {
            try collectVarRefs(uses, if_e.condition.*, allocator);
            try collectVarRefs(uses, if_e.body.*, allocator);
            try collectVarRefs(uses, if_e.orelse_value.*, allocator);
        },
        else => {},
    }
}

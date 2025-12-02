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

/// Variable that needs hoisting due to scope escape
pub const EscapedVar = struct {
    name: []const u8,
    /// The AST node of the initializer expression (for @TypeOf)
    /// null if we can't determine (fall back to anytype or i64)
    init_expr: ?*const ast.Node,
    /// Source: what kind of block declared this var
    source: enum { with_stmt, try_except, for_loop, if_stmt },
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

    // Find variables that are declared inner but used outer
    var iter = declared_in_inner.iterator();
    while (iter.next()) |entry| {
        if (used_at_outer.contains(entry.key_ptr.*)) {
            try result.escaped_vars.append(allocator, entry.value_ptr.*);
        }
    }

    return result;
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
            if (with.optional_vars) |var_name| {
                try decls.put(allocator, var_name, .{
                    .name = var_name,
                    .init_expr = with.context_expr,
                    .source = .with_stmt,
                });
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
                    try decls.put(allocator, exc_name, .{
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
            for (if_s.orelse_) |stmt| {
                try collectAssignments(decls, stmt, .if_stmt, allocator);
                try collectInnerScopeDecls(decls, stmt, allocator);
            }
        },
        .for_stmt => |for_s| {
            // Loop variable
            if (for_s.target.* == .name) {
                const var_name = for_s.target.name.id;
                try decls.put(allocator, var_name, .{
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
    source: EscapedVar.source,
    allocator: std.mem.Allocator,
) !void {
    if (node == .assign) {
        const assign = node.assign;
        if (assign.targets.len > 0) {
            const target = assign.targets[0];
            if (target == .name) {
                const var_name = target.name.id;
                // Only add if not already declared
                if (!decls.contains(var_name)) {
                    try decls.put(allocator, var_name, .{
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
            try uses.put(allocator, n.id, {});
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
            try collectVarRefs(uses, sub.slice.*, allocator);
        },
        .list => |list| {
            for (list.elements) |elem| {
                try collectVarRefs(uses, elem, allocator);
            }
        },
        .tuple => |tuple| {
            for (tuple.elements) |elem| {
                try collectVarRefs(uses, elem, allocator);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                if (key) |k| try collectVarRefs(uses, k.*, allocator);
            }
            for (dict.values) |val| {
                try collectVarRefs(uses, val, allocator);
            }
        },
        .if_expr => |if_e| {
            try collectVarRefs(uses, if_e.test.*, allocator);
            try collectVarRefs(uses, if_e.body.*, allocator);
            try collectVarRefs(uses, if_e.orelse_.*, allocator);
        },
        else => {},
    }
}

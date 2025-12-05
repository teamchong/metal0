/// Shared variable usage analysis for AST traversal
/// Consolidates duplicated code from param_analyzer.zig and try_except.zig
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");

pub const StringSet = hashmap_helper.StringHashMap(void);

/// Configuration for name usage analysis
pub const AnalysisConfig = struct {
    /// Skip yield statements (for generators where yield becomes __gen_result.append)
    skip_yield: bool = false,
    /// Skip parent __init__/__new__ calls (for __init__ methods)
    skip_parent_init: bool = false,
    /// Skip super() method calls (for classes without known parents)
    skip_super_calls: bool = false,
    /// Only check field assignments (self.x = value) in __new__ methods
    only_field_assignments: bool = false,
};

/// Check if a name (variable/parameter) is used anywhere in the body
pub fn isNameUsedInBody(body: []const ast.Node, name: []const u8) bool {
    return isNameUsedInBodyWithConfig(body, name, .{});
}

/// Check if a name is used in body with custom configuration
pub fn isNameUsedInBodyWithConfig(body: []const ast.Node, name: []const u8, config: AnalysisConfig) bool {
    for (body) |stmt| {
        if (isNameUsedInStmtWithConfig(stmt, name, config)) return true;
    }
    return false;
}

/// Check if a name is used in a single statement
pub fn isNameUsedInStmt(stmt: ast.Node, name: []const u8) bool {
    return isNameUsedInStmtWithConfig(stmt, name, .{});
}

fn isNameUsedInStmtWithConfig(stmt: ast.Node, name: []const u8, config: AnalysisConfig) bool {
    return switch (stmt) {
        .expr_stmt => |expr| {
            if (config.skip_parent_init and isParentInitCall(expr.value.*)) return false;
            if (config.skip_super_calls and isSuperMethodCall(expr.value.*)) return false;
            return isNameUsedInExpr(expr.value.*, name);
        },
        .assign => |assign| {
            if (config.skip_parent_init and isParentInitCall(assign.value.*)) return false;
            if (config.skip_super_calls and isSuperMethodCall(assign.value.*)) return false;

            if (config.only_field_assignments) {
                // Only check self.field = value assignments
                for (assign.targets) |target| {
                    if (target == .attribute) {
                        const attr = target.attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            return isNameUsedInExpr(assign.value.*, name);
                        }
                    }
                }
                return false;
            }

            for (assign.targets) |target| {
                if (isNameUsedInExpr(target, name)) return true;
            }
            return isNameUsedInExpr(assign.value.*, name);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                if (config.skip_super_calls and isSuperMethodCall(val.*)) return false;
                return isNameUsedInExpr(val.*, name);
            }
            return false;
        },
        .yield_stmt => |y| {
            if (config.skip_yield) {
                // For generators, still check the yield VALUE
                if (y.value) |v| return isNameUsedInExpr(v.*, name);
                return false;
            }
            if (y.value) |v| return isNameUsedInExpr(v.*, name);
            return false;
        },
        .yield_from_stmt => |y| isNameUsedInExpr(y.value.*, name),
        .if_stmt => |if_stmt| {
            if (isNameUsedInExpr(if_stmt.condition.*, name)) return true;
            if (isNameUsedInBodyWithConfig(if_stmt.body, name, config)) return true;
            if (isNameUsedInBodyWithConfig(if_stmt.else_body, name, config)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isNameUsedInExpr(while_stmt.condition.*, name)) return true;
            if (isNameUsedInBodyWithConfig(while_stmt.body, name, config)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isNameUsedInExpr(for_stmt.iter.*, name)) return true;
            if (isNameUsedInBodyWithConfig(for_stmt.body, name, config)) return true;
            return false;
        },
        .function_def => |func_def| isNameUsedInBodyWithConfig(func_def.body, name, config),
        .class_def => |class_def| isNameUsedInBodyWithConfig(class_def.body, name, config),
        .with_stmt => |with_stmt| {
            if (isNameUsedInExpr(with_stmt.context_expr.*, name)) return true;
            if (isNameUsedInBodyWithConfig(with_stmt.body, name, config)) return true;
            return false;
        },
        .try_stmt => |try_stmt| {
            if (isNameUsedInBodyWithConfig(try_stmt.body, name, config)) return true;
            for (try_stmt.handlers) |handler| {
                if (isNameUsedInBodyWithConfig(handler.body, name, config)) return true;
            }
            if (isNameUsedInBodyWithConfig(try_stmt.else_body, name, config)) return true;
            if (isNameUsedInBodyWithConfig(try_stmt.finalbody, name, config)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            if (isNameUsedInExpr(match_stmt.subject.*, name)) return true;
            for (match_stmt.cases) |case| {
                if (case.guard) |guard| {
                    if (isNameUsedInExpr(guard.*, name)) return true;
                }
                if (isNameUsedInBodyWithConfig(case.body, name, config)) return true;
            }
            return false;
        },
        .aug_assign => |aug| {
            if (isNameUsedInExpr(aug.target.*, name)) return true;
            if (isNameUsedInExpr(aug.value.*, name)) return true;
            return false;
        },
        else => false,
    };
}

/// Check if a name is used in an expression
pub fn isNameUsedInExpr(expr: ast.Node, name: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, name),
        .call => |call| {
            if (isNameUsedInExpr(call.func.*, name)) return true;
            for (call.args) |arg| {
                // Handle starred (*args) and double_starred (**kwargs) unpacking
                if (arg == .starred) {
                    if (isNameUsedInExpr(arg.starred.value.*, name)) return true;
                } else if (arg == .double_starred) {
                    if (isNameUsedInExpr(arg.double_starred.value.*, name)) return true;
                } else if (isNameUsedInExpr(arg, name)) {
                    return true;
                }
            }
            for (call.keyword_args) |kwarg| {
                if (isNameUsedInExpr(kwarg.value, name)) return true;
            }
            return false;
        },
        .binop => |binop| {
            return isNameUsedInExpr(binop.left.*, name) or isNameUsedInExpr(binop.right.*, name);
        },
        .compare => |comp| {
            if (isNameUsedInExpr(comp.left.*, name)) return true;
            for (comp.comparators) |c| {
                if (isNameUsedInExpr(c, name)) return true;
            }
            return false;
        },
        .unaryop => |unary| isNameUsedInExpr(unary.operand.*, name),
        .boolop => |boolop| {
            for (boolop.values) |val| {
                if (isNameUsedInExpr(val, name)) return true;
            }
            return false;
        },
        .subscript => |sub| {
            if (isNameUsedInExpr(sub.value.*, name)) return true;
            switch (sub.slice) {
                .index => |idx| {
                    if (isNameUsedInExpr(idx.*, name)) return true;
                },
                else => {},
            }
            return false;
        },
        .attribute => |attr| isNameUsedInExpr(attr.value.*, name),
        .lambda => |lam| isNameUsedInExpr(lam.body.*, name),
        .list => |list| {
            for (list.elts) |elem| {
                if (isNameUsedInExpr(elem, name)) return true;
            }
            return false;
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                if (isNameUsedInExpr(key, name)) return true;
            }
            for (dict.values) |val| {
                if (isNameUsedInExpr(val, name)) return true;
            }
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                if (isNameUsedInExpr(elem, name)) return true;
            }
            return false;
        },
        .if_expr => |tern| {
            if (isNameUsedInExpr(tern.condition.*, name)) return true;
            if (isNameUsedInExpr(tern.body.*, name)) return true;
            if (isNameUsedInExpr(tern.orelse_value.*, name)) return true;
            return false;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| {
                        if (isNameUsedInExpr(e.node.*, name)) return true;
                    },
                    .format_expr => |fe| {
                        if (isNameUsedInExpr(fe.expr.*, name)) return true;
                    },
                    .conv_expr => |ce| {
                        if (isNameUsedInExpr(ce.expr.*, name)) return true;
                    },
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (isNameUsedInExpr(lc.elt.*, name)) return true;
            for (lc.generators) |gen| {
                if (isNameUsedInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isNameUsedInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (isNameUsedInExpr(dc.key.*, name)) return true;
            if (isNameUsedInExpr(dc.value.*, name)) return true;
            for (dc.generators) |gen| {
                if (isNameUsedInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isNameUsedInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            if (isNameUsedInExpr(ge.elt.*, name)) return true;
            for (ge.generators) |gen| {
                if (isNameUsedInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isNameUsedInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .starred => |starred| isNameUsedInExpr(starred.value.*, name),
        else => false,
    };
}

/// Error type for variable collection operations
pub const CollectError = std.mem.Allocator.Error;

/// Collect all variable names referenced in statements into a set
pub fn collectReferencedVars(stmts: []const ast.Node, vars: *StringSet, allocator: std.mem.Allocator) CollectError!void {
    for (stmts) |stmt| {
        try collectReferencedVarsInStmt(stmt, vars, allocator);
    }
}

fn collectReferencedVarsInStmt(stmt: ast.Node, vars: *StringSet, allocator: std.mem.Allocator) CollectError!void {
    switch (stmt) {
        .expr_stmt => |expr| try collectReferencedVarsInExpr(expr.value.*, vars, allocator),
        .assign => |assign| {
            for (assign.targets) |target| {
                try collectReferencedVarsInExpr(target, vars, allocator);
            }
            try collectReferencedVarsInExpr(assign.value.*, vars, allocator);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| try collectReferencedVarsInExpr(val.*, vars, allocator);
        },
        .if_stmt => |if_stmt| {
            try collectReferencedVarsInExpr(if_stmt.condition.*, vars, allocator);
            try collectReferencedVars(if_stmt.body, vars, allocator);
            try collectReferencedVars(if_stmt.else_body, vars, allocator);
        },
        .while_stmt => |while_stmt| {
            try collectReferencedVarsInExpr(while_stmt.condition.*, vars, allocator);
            try collectReferencedVars(while_stmt.body, vars, allocator);
        },
        .for_stmt => |for_stmt| {
            try collectReferencedVarsInExpr(for_stmt.iter.*, vars, allocator);
            try collectReferencedVars(for_stmt.body, vars, allocator);
        },
        .try_stmt => |try_stmt| {
            try collectReferencedVars(try_stmt.body, vars, allocator);
            for (try_stmt.handlers) |handler| {
                try collectReferencedVars(handler.body, vars, allocator);
            }
            try collectReferencedVars(try_stmt.else_body, vars, allocator);
            try collectReferencedVars(try_stmt.finalbody, vars, allocator);
        },
        .aug_assign => |aug| {
            try collectReferencedVarsInExpr(aug.target.*, vars, allocator);
            try collectReferencedVarsInExpr(aug.value.*, vars, allocator);
        },
        .class_def => |class_def| {
            // Find variables referenced in class methods that come from outer scope
            // Handles cases like: for badval in [...]: class A: def f(self): return badval
            for (class_def.body) |class_stmt| {
                if (class_stmt == .function_def) {
                    const method = class_stmt.function_def;
                    try collectReferencedVars(method.body, vars, allocator);
                }
            }
        },
        .function_def => |func_def| {
            // Find variables referenced in nested function bodies
            try collectReferencedVars(func_def.body, vars, allocator);
        },
        else => {},
    }
}

/// Collect all variable names referenced in an expression
pub fn collectReferencedVarsInExpr(expr: ast.Node, vars: *StringSet, allocator: std.mem.Allocator) CollectError!void {
    // allocator passed through for recursive calls
    switch (expr) {
        .name => |name_node| {
            try vars.put(name_node.id, {});
        },
        .attribute => |attr| {
            try collectReferencedVarsInExpr(attr.value.*, vars, allocator);
        },
        .subscript => |sub| {
            try collectReferencedVarsInExpr(sub.value.*, vars, allocator);
            if (sub.slice == .index) {
                try collectReferencedVarsInExpr(sub.slice.index.*, vars, allocator);
            }
        },
        .call => |call| {
            // Skip super() method calls - they're stripped during codegen
            if (isSuperMethodCall(ast.Node{ .call = call })) return;
            try collectReferencedVarsInExpr(call.func.*, vars, allocator);
            for (call.args) |arg| {
                try collectReferencedVarsInExpr(arg, vars, allocator);
            }
        },
        .binop => |binop| {
            try collectReferencedVarsInExpr(binop.left.*, vars, allocator);
            try collectReferencedVarsInExpr(binop.right.*, vars, allocator);
        },
        .compare => |cmp| {
            try collectReferencedVarsInExpr(cmp.left.*, vars, allocator);
            for (cmp.comparators) |comp| {
                try collectReferencedVarsInExpr(comp, vars, allocator);
            }
        },
        .unaryop => |unary| {
            try collectReferencedVarsInExpr(unary.operand.*, vars, allocator);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectReferencedVarsInExpr(elem, vars, allocator);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try collectReferencedVarsInExpr(key, vars, allocator);
            }
            for (dict.values) |val| {
                try collectReferencedVarsInExpr(val, vars, allocator);
            }
        },
        .starred => |starred| {
            try collectReferencedVarsInExpr(starred.value.*, vars, allocator);
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectReferencedVarsInExpr(elem, vars, allocator);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                try collectReferencedVarsInExpr(val, vars, allocator);
            }
        },
        .if_expr => |if_expr| {
            try collectReferencedVarsInExpr(if_expr.condition.*, vars, allocator);
            try collectReferencedVarsInExpr(if_expr.body.*, vars, allocator);
            try collectReferencedVarsInExpr(if_expr.orelse_value.*, vars, allocator);
        },
        else => {},
    }
}

// ============================================================================
// Helper functions for detecting special call patterns
// ============================================================================

/// Check if an expression is a parent __init__ or __new__ call
/// Matches: Parent.__init__(self, ...) or super().__init__(...) or Parent.__new__(cls, ...)
pub fn isParentInitCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;

    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (std.mem.eql(u8, attr.attr, "__init__") or std.mem.eql(u8, attr.attr, "__new__")) {
            return true;
        }
    }
    return false;
}

/// Check if an expression is a super() method call
/// Matches: super().__buffer__(flags), super().method(), etc.
pub fn isSuperMethodCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;

    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (attr.value.* == .call) {
            const base_call = attr.value.call;
            if (base_call.func.* == .name and std.mem.eql(u8, base_call.func.name.id, "super")) {
                return true;
            }
        }
    }
    return false;
}

// ============================================================================
// Specialized analysis functions (wrappers around configurable version)
// ============================================================================

/// Check if name is used excluding yield expressions (for generators)
pub fn isNameUsedInBodyExcludingYield(body: []const ast.Node, name: []const u8) bool {
    return isNameUsedInBodyWithConfig(body, name, .{ .skip_yield = true });
}

/// Check if name is used in __init__ body, excluding parent __init__ calls
pub fn isNameUsedInInitBody(body: []const ast.Node, name: []const u8) bool {
    return isNameUsedInBodyWithConfig(body, name, .{ .skip_parent_init = true });
}

/// Check if name is used in __new__ body for field assignments only
pub fn isNameUsedInNewForInit(body: []const ast.Node, name: []const u8) bool {
    return isNameUsedInBodyWithConfig(body, name, .{ .only_field_assignments = true });
}

/// Check if name is used excluding super() method calls
pub fn isNameUsedInBodyExcludingSuperCalls(body: []const ast.Node, name: []const u8) bool {
    return isNameUsedInBodyWithConfig(body, name, .{ .skip_super_calls = true });
}

/// Check if a parameter is used inside a nested function (closure capture)
pub fn isParameterUsedInNestedFunction(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .function_def => |func_def| {
                if (isNameUsedInBody(func_def.body, param_name)) return true;
            },
            .if_stmt => |if_stmt| {
                if (isParameterUsedInNestedFunction(if_stmt.body, param_name)) return true;
                if (isParameterUsedInNestedFunction(if_stmt.else_body, param_name)) return true;
            },
            .while_stmt => |while_stmt| {
                if (isParameterUsedInNestedFunction(while_stmt.body, param_name)) return true;
            },
            .for_stmt => |for_stmt| {
                if (isParameterUsedInNestedFunction(for_stmt.body, param_name)) return true;
            },
            else => {},
        }
    }
    return false;
}

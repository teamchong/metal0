/// Parameter usage analysis for decorator and higher-order function detection
/// Uses shared variable_usage module for core AST traversal
const std = @import("std");
const ast = @import("analysis.ast");
const self_analyzer = @import("self_analyzer.zig");
const UnittestMethodNames = self_analyzer.unittest_assertion_methods;

// Import shared variable usage analysis
const variable_usage = @import("../../analysis/variable_usage.zig");

// Re-export core functions from shared module
pub const isNameUsedInBody = variable_usage.isNameUsedInBody;
pub const isNameUsedInStmt = variable_usage.isNameUsedInStmt;
pub const isNameUsedInExpr = variable_usage.isNameUsedInExpr;
pub const isNameUsedInBodyExcludingYield = variable_usage.isNameUsedInBodyExcludingYield;
pub const isNameUsedInInitBody = variable_usage.isNameUsedInInitBody;
pub const isNameUsedInNewForInit = variable_usage.isNameUsedInNewForInit;
pub const isNameUsedInBodyExcludingSuperCalls = variable_usage.isNameUsedInBodyExcludingSuperCalls;
pub const isParameterUsedInNestedFunction = variable_usage.isParameterUsedInNestedFunction;
pub const isParentInitCall = variable_usage.isParentInitCall;
pub const isSuperMethodCall = variable_usage.isSuperMethodCall;

// ============================================================================
// Init body analysis functions
// ============================================================================

/// Check if a variable name is assigned (not just used) in the body
/// This is used to detect when a parameter name would conflict with a local variable
/// e.g., `def __init__(self, d): if not d: d = {}`
/// In this case, parameter `d` should be renamed to avoid shadowing local `d`
pub fn isNameAssignedInInitBody(body: []const ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameAssignedInStmt(stmt, name)) return true;
    }
    return false;
}

fn isNameAssignedInStmt(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (target == .name and std.mem.eql(u8, target.name.id, name)) return true;
            }
            return false;
        },
        .aug_assign => |aug| {
            if (aug.target.* == .name and std.mem.eql(u8, aug.target.name.id, name)) return true;
            return false;
        },
        .ann_assign => |ann| {
            if (ann.target.* == .name and std.mem.eql(u8, ann.target.name.id, name)) return true;
            return false;
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            for (if_stmt.else_body) |s| if (isNameAssignedInStmt(s, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isNameAssignedInStmt(s, name)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            // Check if for loop variable is the name
            if (for_stmt.target.* == .name and std.mem.eql(u8, for_stmt.target.name.id, name)) return true;
            for (for_stmt.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isNameAssignedInStmt(s, name)) return true;
            }
            return false;
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            for (try_stmt.handlers) |handler| {
                // Check exception variable binding
                if (handler.name) |exc_name| {
                    if (std.mem.eql(u8, exc_name, name)) return true;
                }
                for (handler.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            }
            for (try_stmt.else_body) |s| if (isNameAssignedInStmt(s, name)) return true;
            for (try_stmt.finalbody) |s| if (isNameAssignedInStmt(s, name)) return true;
            return false;
        },
        .with_stmt => |with_stmt| {
            // Check 'as' binding
            if (with_stmt.optional_vars) |opt_vars| {
                if (opt_vars.* == .name and std.mem.eql(u8, opt_vars.name.id, name)) return true;
            }
            for (with_stmt.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            for (match_stmt.cases) |case| {
                for (case.body) |s| if (isNameAssignedInStmt(s, name)) return true;
            }
            return false;
        },
        // Note: we don't recurse into nested function_def/class_def since those
        // have their own scope and won't cause shadowing at our level
        else => false,
    };
}

/// Check if __init__ body only raises an exception (no actual initialization)
/// Returns true if the body consists only of: raise, pass, docstring, or parent init calls
pub fn isInitBodyOnlyRaises(body: []const ast.Node) bool {
    if (body.len == 0) return false;

    var has_raise = false;
    for (body) |stmt| {
        switch (stmt) {
            .raise_stmt => has_raise = true,
            .pass => {}, // pass is allowed
            .expr_stmt => |expr| {
                // Only allow docstrings (string constants)
                if (expr.value.* != .constant or expr.value.constant.value != .string) {
                    return false;
                }
            },
            else => return false, // Any other statement means it's not just a raise
        }
    }
    return has_raise;
}

/// Check if the function body uses locals() builtin
/// This is important because locals() requires all parameters to be accessible
/// If locals() is used, we cannot discard any parameters
pub fn usesLocalsBuiltin(body: []const ast.Node) bool {
    for (body) |stmt| {
        if (usesLocalsInStmt(stmt)) return true;
    }
    return false;
}

fn usesLocalsInStmt(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |expr| usesLocalsInExpr(expr.value.*),
        .assign => |assign| {
            if (usesLocalsInExpr(assign.value.*)) return true;
            return false;
        },
        .return_stmt => |ret| {
            if (ret.value) |v| return usesLocalsInExpr(v.*);
            return false;
        },
        .if_stmt => |i| {
            if (usesLocalsInExpr(i.condition.*)) return true;
            for (i.body) |s| if (usesLocalsInStmt(s)) return true;
            for (i.else_body) |s| if (usesLocalsInStmt(s)) return true;
            return false;
        },
        .for_stmt => |f| {
            if (usesLocalsInExpr(f.iter.*)) return true;
            for (f.body) |s| if (usesLocalsInStmt(s)) return true;
            if (f.orelse_body) |ob| for (ob) |s| if (usesLocalsInStmt(s)) return true;
            return false;
        },
        .while_stmt => |w| {
            if (usesLocalsInExpr(w.condition.*)) return true;
            for (w.body) |s| if (usesLocalsInStmt(s)) return true;
            if (w.orelse_body) |ob| for (ob) |s| if (usesLocalsInStmt(s)) return true;
            return false;
        },
        .try_stmt => |t| {
            for (t.body) |s| if (usesLocalsInStmt(s)) return true;
            for (t.handlers) |h| for (h.body) |s| if (usesLocalsInStmt(s)) return true;
            for (t.else_body) |s| if (usesLocalsInStmt(s)) return true;
            for (t.finalbody) |s| if (usesLocalsInStmt(s)) return true;
            return false;
        },
        .with_stmt => |w| {
            if (usesLocalsInExpr(w.context_expr.*)) return true;
            for (w.body) |s| if (usesLocalsInStmt(s)) return true;
            return false;
        },
        else => false,
    };
}

fn usesLocalsInExpr(expr: ast.Node) bool {
    return switch (expr) {
        .call => |call| {
            // Check if it's a call to locals()
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "locals")) {
                return true;
            }
            // Check arguments recursively
            if (usesLocalsInExpr(call.func.*)) return true;
            for (call.args) |arg| if (usesLocalsInExpr(arg)) return true;
            for (call.keyword_args) |kwarg| if (usesLocalsInExpr(kwarg.value)) return true;
            return false;
        },
        .binop => |b| usesLocalsInExpr(b.left.*) or usesLocalsInExpr(b.right.*),
        .unaryop => |u| usesLocalsInExpr(u.operand.*),
        .compare => |c| {
            if (usesLocalsInExpr(c.left.*)) return true;
            for (c.comparators) |comp| if (usesLocalsInExpr(comp)) return true;
            return false;
        },
        .subscript => |s| usesLocalsInExpr(s.value.*),
        .attribute => |a| usesLocalsInExpr(a.value.*),
        .if_expr => |i| usesLocalsInExpr(i.condition.*) or usesLocalsInExpr(i.body.*) or usesLocalsInExpr(i.orelse_value.*),
        .list => |l| {
            for (l.elts) |e| if (usesLocalsInExpr(e)) return true;
            return false;
        },
        .tuple => |t| {
            for (t.elts) |e| if (usesLocalsInExpr(e)) return true;
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| if (usesLocalsInExpr(k)) return true;
            for (d.values) |v| if (usesLocalsInExpr(v)) return true;
            return false;
        },
        .listcomp => |lc| {
            if (usesLocalsInExpr(lc.elt.*)) return true;
            // Check generators (for x in <iter> if <cond>)
            for (lc.generators) |gen| {
                if (usesLocalsInExpr(gen.iter.*)) return true;
                for (gen.ifs) |if_cond| if (usesLocalsInExpr(if_cond)) return true;
            }
            return false;
        },
        .dictcomp => |dc| {
            if (usesLocalsInExpr(dc.key.*) or usesLocalsInExpr(dc.value.*)) return true;
            // Check generators
            for (dc.generators) |gen| {
                if (usesLocalsInExpr(gen.iter.*)) return true;
                for (gen.ifs) |if_cond| if (usesLocalsInExpr(if_cond)) return true;
            }
            return false;
        },
        .genexp => |ge| {
            if (usesLocalsInExpr(ge.elt.*)) return true;
            // Check generators
            for (ge.generators) |gen| {
                if (usesLocalsInExpr(gen.iter.*)) return true;
                for (gen.ifs) |if_cond| if (usesLocalsInExpr(if_cond)) return true;
            }
            return false;
        },
        else => false,
    };
}

// ============================================================================
// Parameter-specific analysis functions (not in shared module)
// ============================================================================

/// Check if a parameter is called as a function in the body
pub fn isParameterCalled(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        if (isParameterCalledInStmt(stmt, param_name)) return true;
    }
    return false;
}

/// Check if a parameter is used as a function (called somewhere in the body)
pub fn isParameterUsedAsFunction(body: []const ast.Node, param_name: []const u8) bool {
    return isParameterCalled(body, param_name);
}

fn isParameterCalledInStmt(stmt: ast.Node, param_name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| isParameterCalledInExpr(expr.value.*, param_name),
        .assign => |assign| isParameterCalledInExpr(assign.value.*, param_name),
        .aug_assign => |aug| isParameterCalledInExpr(aug.value.*, param_name),
        .ann_assign => |ann| if (ann.value) |v| isParameterCalledInExpr(v.*, param_name) else false,
        .return_stmt => |ret| if (ret.value) |val| isParameterCalledInExpr(val.*, param_name) else false,
        .if_stmt => |if_stmt| {
            if (isParameterCalledInExpr(if_stmt.condition.*, param_name)) return true;
            for (if_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            for (if_stmt.else_body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isParameterCalledInExpr(while_stmt.condition.*, param_name)) return true;
            for (while_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isParameterCalledInExpr(for_stmt.iter.*, param_name)) return true;
            for (for_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            }
            return false;
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            }
            for (try_stmt.else_body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            for (try_stmt.finalbody) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            return false;
        },
        .with_stmt => |with_stmt| {
            if (isParameterCalledInExpr(with_stmt.context_expr.*, param_name)) return true;
            for (with_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            if (isParameterCalledInExpr(match_stmt.subject.*, param_name)) return true;
            for (match_stmt.cases) |case| {
                if (case.guard) |g| if (isParameterCalledInExpr(g.*, param_name)) return true;
                for (case.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            }
            return false;
        },
        .function_def => |func_def| {
            for (func_def.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            return false;
        },
        .class_def => |class_def| {
            for (class_def.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
            return false;
        },
        .assert_stmt => |assert_stmt| {
            if (isParameterCalledInExpr(assert_stmt.condition.*, param_name)) return true;
            if (assert_stmt.msg) |m| if (isParameterCalledInExpr(m.*, param_name)) return true;
            return false;
        },
        .raise_stmt => |raise_stmt| {
            if (raise_stmt.exc) |e| if (isParameterCalledInExpr(e.*, param_name)) return true;
            if (raise_stmt.cause) |c| if (isParameterCalledInExpr(c.*, param_name)) return true;
            return false;
        },
        else => false,
    };
}

fn isParameterCalledInExpr(expr: ast.Node, param_name: []const u8) bool {
    return switch (expr) {
        .call => |call| {
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, param_name)) {
                return true;
            }
            for (call.args) |arg| {
                if (isParameterCalledInExpr(arg, param_name)) return true;
            }
            // Check keyword arguments
            for (call.keyword_args) |kw| {
                if (isParameterCalledInExpr(kw.value, param_name)) return true;
            }
            return false;
        },
        .lambda => |lam| isParameterCalledInExpr(lam.body.*, param_name),
        .binop => |binop| {
            return isParameterCalledInExpr(binop.left.*, param_name) or
                isParameterCalledInExpr(binop.right.*, param_name);
        },
        .compare => |comp| {
            if (isParameterCalledInExpr(comp.left.*, param_name)) return true;
            for (comp.comparators) |c| {
                if (isParameterCalledInExpr(c, param_name)) return true;
            }
            return false;
        },
        .unaryop => |u| isParameterCalledInExpr(u.operand.*, param_name),
        .boolop => |b| {
            for (b.values) |v| {
                if (isParameterCalledInExpr(v, param_name)) return true;
            }
            return false;
        },
        .if_expr => |ie| {
            if (isParameterCalledInExpr(ie.condition.*, param_name)) return true;
            if (isParameterCalledInExpr(ie.body.*, param_name)) return true;
            if (isParameterCalledInExpr(ie.orelse_value.*, param_name)) return true;
            return false;
        },
        .subscript => |sub| {
            if (isParameterCalledInExpr(sub.value.*, param_name)) return true;
            return switch (sub.slice) {
                .index => |idx| isParameterCalledInExpr(idx.*, param_name),
                .slice => |sr| {
                    if (sr.lower) |l| if (isParameterCalledInExpr(l.*, param_name)) return true;
                    if (sr.upper) |u| if (isParameterCalledInExpr(u.*, param_name)) return true;
                    if (sr.step) |s| if (isParameterCalledInExpr(s.*, param_name)) return true;
                    return false;
                },
            };
        },
        .list => |lst| {
            for (lst.elts) |e| {
                if (isParameterCalledInExpr(e, param_name)) return true;
            }
            return false;
        },
        .tuple => |tup| {
            for (tup.elts) |e| {
                if (isParameterCalledInExpr(e, param_name)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (isParameterCalledInExpr(k, param_name)) return true;
            }
            for (d.values) |v| {
                if (isParameterCalledInExpr(v, param_name)) return true;
            }
            return false;
        },
        .fstring => |fs| {
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| if (isParameterCalledInExpr(e.node.*, param_name)) return true,
                    .format_expr => |fe| if (isParameterCalledInExpr(fe.expr.*, param_name)) return true,
                    .conv_expr => |ce| if (isParameterCalledInExpr(ce.expr.*, param_name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (isParameterCalledInExpr(lc.elt.*, param_name)) return true;
            for (lc.generators) |gen| {
                if (isParameterCalledInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParameterCalledInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .dictcomp => |dc| {
            if (isParameterCalledInExpr(dc.key.*, param_name)) return true;
            if (isParameterCalledInExpr(dc.value.*, param_name)) return true;
            for (dc.generators) |gen| {
                if (isParameterCalledInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParameterCalledInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .genexp => |ge| {
            if (isParameterCalledInExpr(ge.elt.*, param_name)) return true;
            for (ge.generators) |gen| {
                if (isParameterCalledInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParameterCalledInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .starred => |st| isParameterCalledInExpr(st.value.*, param_name),
        .attribute => |attr| isParameterCalledInExpr(attr.value.*, param_name),
        else => false,
    };
}

/// Check if a parameter is used as an iterator in a for loop or comprehension
pub fn isParameterUsedAsIterator(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .for_stmt => |for_stmt| {
                if (for_stmt.iter.* == .name and std.mem.eql(u8, for_stmt.iter.name.id, param_name)) {
                    return true;
                }
                if (isParameterUsedAsIterator(for_stmt.body, param_name)) return true;
                if (for_stmt.orelse_body) |orelse_body| {
                    if (isParameterUsedAsIterator(orelse_body, param_name)) return true;
                }
            },
            .if_stmt => |if_stmt| {
                if (isParameterUsedAsIterator(if_stmt.body, param_name)) return true;
                if (isParameterUsedAsIterator(if_stmt.else_body, param_name)) return true;
            },
            .while_stmt => |while_stmt| {
                if (isParameterUsedAsIterator(while_stmt.body, param_name)) return true;
                if (while_stmt.orelse_body) |orelse_body| {
                    if (isParameterUsedAsIterator(orelse_body, param_name)) return true;
                }
            },
            .function_def => |func_def| {
                if (isParameterUsedAsIterator(func_def.body, param_name)) return true;
            },
            .class_def => |class_def| {
                if (isParameterUsedAsIterator(class_def.body, param_name)) return true;
            },
            .return_stmt => |ret| {
                if (ret.value) |val| {
                    if (isParamIteratorInExpr(val.*, param_name)) return true;
                }
            },
            .assign => |assign| {
                if (isParamIteratorInExpr(assign.value.*, param_name)) return true;
            },
            .expr_stmt => |expr| {
                if (isParamIteratorInExpr(expr.value.*, param_name)) return true;
            },
            .try_stmt => |try_stmt| {
                if (isParameterUsedAsIterator(try_stmt.body, param_name)) return true;
                for (try_stmt.handlers) |handler| {
                    if (isParameterUsedAsIterator(handler.body, param_name)) return true;
                }
                if (isParameterUsedAsIterator(try_stmt.else_body, param_name)) return true;
                if (isParameterUsedAsIterator(try_stmt.finalbody, param_name)) return true;
            },
            .with_stmt => |with_stmt| {
                if (isParameterUsedAsIterator(with_stmt.body, param_name)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (isParameterUsedAsIterator(case.body, param_name)) return true;
                }
            },
            else => {},
        }
    }
    return false;
}

fn isParamIteratorInExpr(expr: ast.Node, param_name: []const u8) bool {
    return switch (expr) {
        .listcomp => |lc| {
            for (lc.generators) |gen| {
                if (gen.iter.* == .name and std.mem.eql(u8, gen.iter.name.id, param_name)) {
                    return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            for (dc.generators) |gen| {
                if (gen.iter.* == .name and std.mem.eql(u8, gen.iter.name.id, param_name)) {
                    return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            for (ge.generators) |gen| {
                if (gen.iter.* == .name and std.mem.eql(u8, gen.iter.name.id, param_name)) {
                    return true;
                }
            }
            return false;
        },
        else => false,
    };
}

/// Check if first param is used in ways that don't get dispatched to unittest methods.
pub fn isFirstParamUsedNonUnittest(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        if (isFirstParamUsedNonUnittestInStmt(stmt, param_name)) return true;
    }
    return false;
}

fn isFirstParamUsedNonUnittestInStmt(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| isFirstParamUsedNonUnittestInExpr(expr.value.*, name),
        .assign => |assign| {
            for (assign.targets) |target| {
                if (isFirstParamUsedNonUnittestInExpr(target, name)) return true;
            }
            return isFirstParamUsedNonUnittestInExpr(assign.value.*, name);
        },
        .aug_assign => |aug| {
            if (isFirstParamUsedNonUnittestInExpr(aug.target.*, name)) return true;
            return isFirstParamUsedNonUnittestInExpr(aug.value.*, name);
        },
        .ann_assign => |ann| {
            if (isFirstParamUsedNonUnittestInExpr(ann.target.*, name)) return true;
            if (ann.value) |v| if (isFirstParamUsedNonUnittestInExpr(v.*, name)) return true;
            return false;
        },
        .return_stmt => |ret| if (ret.value) |val| isFirstParamUsedNonUnittestInExpr(val.*, name) else false,
        .if_stmt => |if_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(if_stmt.condition.*, name)) return true;
            if (isFirstParamUsedNonUnittest(if_stmt.body, name)) return true;
            if (isFirstParamUsedNonUnittest(if_stmt.else_body, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(while_stmt.condition.*, name)) return true;
            if (isFirstParamUsedNonUnittest(while_stmt.body, name)) return true;
            if (while_stmt.orelse_body) |orelse_body| {
                if (isFirstParamUsedNonUnittest(orelse_body, name)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(for_stmt.iter.*, name)) return true;
            if (isFirstParamUsedNonUnittest(for_stmt.body, name)) return true;
            if (for_stmt.orelse_body) |orelse_body| {
                if (isFirstParamUsedNonUnittest(orelse_body, name)) return true;
            }
            return false;
        },
        .function_def => |func_def| isFirstParamUsedNonUnittest(func_def.body, name),
        .class_def => |class_def| isFirstParamUsedNonUnittest(class_def.body, name),
        .with_stmt => |with_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(with_stmt.context_expr.*, name)) return true;
            if (isFirstParamUsedNonUnittest(with_stmt.body, name)) return true;
            return false;
        },
        .try_stmt => |try_stmt| {
            if (isFirstParamUsedNonUnittest(try_stmt.body, name)) return true;
            for (try_stmt.handlers) |handler| {
                if (isFirstParamUsedNonUnittest(handler.body, name)) return true;
            }
            if (isFirstParamUsedNonUnittest(try_stmt.else_body, name)) return true;
            if (isFirstParamUsedNonUnittest(try_stmt.finalbody, name)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(match_stmt.subject.*, name)) return true;
            for (match_stmt.cases) |case| {
                if (case.guard) |g| if (isFirstParamUsedNonUnittestInExpr(g.*, name)) return true;
                if (isFirstParamUsedNonUnittest(case.body, name)) return true;
            }
            return false;
        },
        .assert_stmt => |assert_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(assert_stmt.condition.*, name)) return true;
            if (assert_stmt.msg) |m| if (isFirstParamUsedNonUnittestInExpr(m.*, name)) return true;
            return false;
        },
        .raise_stmt => |raise_stmt| {
            if (raise_stmt.exc) |e| if (isFirstParamUsedNonUnittestInExpr(e.*, name)) return true;
            if (raise_stmt.cause) |c| if (isFirstParamUsedNonUnittestInExpr(c.*, name)) return true;
            return false;
        },
        else => false,
    };
}

fn isFirstParamUsedNonUnittestInExpr(expr: ast.Node, name: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, name),
        .call => |call| {
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, name)) {
                    if (UnittestMethodNames.has(attr.attr)) {
                        for (call.args) |arg| {
                            if (isFirstParamUsedNonUnittestInExpr(arg, name)) return true;
                        }
                        for (call.keyword_args) |kw| {
                            if (isFirstParamUsedNonUnittestInExpr(kw.value, name)) return true;
                        }
                        return false;
                    }
                }
            }
            if (isFirstParamUsedNonUnittestInExpr(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (isFirstParamUsedNonUnittestInExpr(arg, name)) return true;
            }
            for (call.keyword_args) |kw| {
                if (isFirstParamUsedNonUnittestInExpr(kw.value, name)) return true;
            }
            return false;
        },
        .binop => |binop| {
            return isFirstParamUsedNonUnittestInExpr(binop.left.*, name) or
                isFirstParamUsedNonUnittestInExpr(binop.right.*, name);
        },
        .compare => |comp| {
            if (isFirstParamUsedNonUnittestInExpr(comp.left.*, name)) return true;
            for (comp.comparators) |c| {
                if (isFirstParamUsedNonUnittestInExpr(c, name)) return true;
            }
            return false;
        },
        .unaryop => |unary| isFirstParamUsedNonUnittestInExpr(unary.operand.*, name),
        .boolop => |boolop| {
            for (boolop.values) |val| {
                if (isFirstParamUsedNonUnittestInExpr(val, name)) return true;
            }
            return false;
        },
        .subscript => |sub| {
            if (isFirstParamUsedNonUnittestInExpr(sub.value.*, name)) return true;
            switch (sub.slice) {
                .index => |idx| {
                    if (isFirstParamUsedNonUnittestInExpr(idx.*, name)) return true;
                },
                .slice => |range| {
                    if (range.lower) |l| if (isFirstParamUsedNonUnittestInExpr(l.*, name)) return true;
                    if (range.upper) |u| if (isFirstParamUsedNonUnittestInExpr(u.*, name)) return true;
                    if (range.step) |s| if (isFirstParamUsedNonUnittestInExpr(s.*, name)) return true;
                },
            }
            return false;
        },
        .attribute => |attr| isFirstParamUsedNonUnittestInExpr(attr.value.*, name),
        .lambda => |lam| isFirstParamUsedNonUnittestInExpr(lam.body.*, name),
        .list => |list| {
            for (list.elts) |elem| {
                if (isFirstParamUsedNonUnittestInExpr(elem, name)) return true;
            }
            return false;
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                if (isFirstParamUsedNonUnittestInExpr(key, name)) return true;
            }
            for (dict.values) |val| {
                if (isFirstParamUsedNonUnittestInExpr(val, name)) return true;
            }
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                if (isFirstParamUsedNonUnittestInExpr(elem, name)) return true;
            }
            return false;
        },
        .if_expr => |tern| {
            if (isFirstParamUsedNonUnittestInExpr(tern.condition.*, name)) return true;
            if (isFirstParamUsedNonUnittestInExpr(tern.body.*, name)) return true;
            if (isFirstParamUsedNonUnittestInExpr(tern.orelse_value.*, name)) return true;
            return false;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (isFirstParamUsedNonUnittestInExpr(e.node.*, name)) return true,
                    .format_expr => |fe| if (isFirstParamUsedNonUnittestInExpr(fe.expr.*, name)) return true,
                    .conv_expr => |ce| if (isFirstParamUsedNonUnittestInExpr(ce.expr.*, name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (isFirstParamUsedNonUnittestInExpr(lc.elt.*, name)) return true;
            for (lc.generators) |gen| {
                if (isFirstParamUsedNonUnittestInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isFirstParamUsedNonUnittestInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (isFirstParamUsedNonUnittestInExpr(dc.key.*, name)) return true;
            if (isFirstParamUsedNonUnittestInExpr(dc.value.*, name)) return true;
            for (dc.generators) |gen| {
                if (isFirstParamUsedNonUnittestInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isFirstParamUsedNonUnittestInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            if (isFirstParamUsedNonUnittestInExpr(ge.elt.*, name)) return true;
            for (ge.generators) |gen| {
                if (isFirstParamUsedNonUnittestInExpr(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (isFirstParamUsedNonUnittestInExpr(cond, name)) return true;
                }
            }
            return false;
        },
        .starred => |st| isFirstParamUsedNonUnittestInExpr(st.value.*, name),
        else => false,
    };
}

/// Check if a parameter is compared to a string constant using == or !=
pub fn isParameterComparedToString(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        if (isParamComparedToStringInStmt(stmt, param_name)) return true;
    }
    return false;
}

fn isParamComparedToStringInStmt(stmt: ast.Node, param_name: []const u8) bool {
    return switch (stmt) {
        .if_stmt => |if_stmt| {
            if (isParamComparedToStringInExpr(if_stmt.condition.*, param_name)) return true;
            if (isParameterComparedToString(if_stmt.body, param_name)) return true;
            if (isParameterComparedToString(if_stmt.else_body, param_name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isParamComparedToStringInExpr(while_stmt.condition.*, param_name)) return true;
            if (isParameterComparedToString(while_stmt.body, param_name)) return true;
            if (while_stmt.orelse_body) |orelse_body| {
                if (isParameterComparedToString(orelse_body, param_name)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isParameterComparedToString(for_stmt.body, param_name)) return true;
            if (for_stmt.orelse_body) |orelse_body| {
                if (isParameterComparedToString(orelse_body, param_name)) return true;
            }
            return false;
        },
        .return_stmt => |ret| {
            if (ret.value) |val| return isParamComparedToStringInExpr(val.*, param_name);
            return false;
        },
        .assign => |assign| isParamComparedToStringInExpr(assign.value.*, param_name),
        .aug_assign => |aug| isParamComparedToStringInExpr(aug.value.*, param_name),
        .ann_assign => |ann| if (ann.value) |v| isParamComparedToStringInExpr(v.*, param_name) else false,
        .expr_stmt => |expr| isParamComparedToStringInExpr(expr.value.*, param_name),
        .function_def => |func_def| isParameterComparedToString(func_def.body, param_name),
        .class_def => |class_def| isParameterComparedToString(class_def.body, param_name),
        .try_stmt => |try_stmt| {
            if (isParameterComparedToString(try_stmt.body, param_name)) return true;
            for (try_stmt.handlers) |handler| {
                if (isParameterComparedToString(handler.body, param_name)) return true;
            }
            if (isParameterComparedToString(try_stmt.else_body, param_name)) return true;
            if (isParameterComparedToString(try_stmt.finalbody, param_name)) return true;
            return false;
        },
        .with_stmt => |with_stmt| {
            if (isParamComparedToStringInExpr(with_stmt.context_expr.*, param_name)) return true;
            if (isParameterComparedToString(with_stmt.body, param_name)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            if (isParamComparedToStringInExpr(match_stmt.subject.*, param_name)) return true;
            for (match_stmt.cases) |case| {
                if (case.guard) |g| if (isParamComparedToStringInExpr(g.*, param_name)) return true;
                if (isParameterComparedToString(case.body, param_name)) return true;
            }
            return false;
        },
        .assert_stmt => |assert_stmt| {
            if (isParamComparedToStringInExpr(assert_stmt.condition.*, param_name)) return true;
            if (assert_stmt.msg) |m| if (isParamComparedToStringInExpr(m.*, param_name)) return true;
            return false;
        },
        else => false,
    };
}

fn isParamComparedToStringInExpr(expr: ast.Node, param_name: []const u8) bool {
    return switch (expr) {
        .compare => |comp| {
            if (comp.left.* == .name and std.mem.eql(u8, comp.left.name.id, param_name)) {
                for (comp.comparators) |comparator| {
                    if (comparator == .constant and comparator.constant.value == .string) {
                        return true;
                    }
                }
            }
            if (comp.left.* == .constant and comp.left.constant.value == .string) {
                for (comp.comparators) |comparator| {
                    if (comparator == .name and std.mem.eql(u8, comparator.name.id, param_name)) {
                        return true;
                    }
                }
            }
            return false;
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                if (isParamComparedToStringInExpr(val, param_name)) return true;
            }
            return false;
        },
        .if_expr => |tern| {
            if (isParamComparedToStringInExpr(tern.condition.*, param_name)) return true;
            if (isParamComparedToStringInExpr(tern.body.*, param_name)) return true;
            if (isParamComparedToStringInExpr(tern.orelse_value.*, param_name)) return true;
            return false;
        },
        .call => |call| {
            for (call.args) |arg| {
                if (isParamComparedToStringInExpr(arg, param_name)) return true;
            }
            for (call.keyword_args) |kw| {
                if (isParamComparedToStringInExpr(kw.value, param_name)) return true;
            }
            return false;
        },
        .binop => |b| {
            if (isParamComparedToStringInExpr(b.left.*, param_name)) return true;
            if (isParamComparedToStringInExpr(b.right.*, param_name)) return true;
            return false;
        },
        .unaryop => |u| isParamComparedToStringInExpr(u.operand.*, param_name),
        .subscript => |sub| {
            if (isParamComparedToStringInExpr(sub.value.*, param_name)) return true;
            return switch (sub.slice) {
                .index => |idx| isParamComparedToStringInExpr(idx.*, param_name),
                .slice => |sr| {
                    if (sr.lower) |l| if (isParamComparedToStringInExpr(l.*, param_name)) return true;
                    if (sr.upper) |up| if (isParamComparedToStringInExpr(up.*, param_name)) return true;
                    if (sr.step) |s| if (isParamComparedToStringInExpr(s.*, param_name)) return true;
                    return false;
                },
            };
        },
        .list => |lst| {
            for (lst.elts) |e| {
                if (isParamComparedToStringInExpr(e, param_name)) return true;
            }
            return false;
        },
        .tuple => |tup| {
            for (tup.elts) |e| {
                if (isParamComparedToStringInExpr(e, param_name)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (isParamComparedToStringInExpr(k, param_name)) return true;
            }
            for (d.values) |v| {
                if (isParamComparedToStringInExpr(v, param_name)) return true;
            }
            return false;
        },
        .fstring => |fs| {
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| if (isParamComparedToStringInExpr(e.node.*, param_name)) return true,
                    .format_expr => |fe| if (isParamComparedToStringInExpr(fe.expr.*, param_name)) return true,
                    .conv_expr => |ce| if (isParamComparedToStringInExpr(ce.expr.*, param_name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .lambda => |lam| isParamComparedToStringInExpr(lam.body.*, param_name),
        .listcomp => |lc| {
            if (isParamComparedToStringInExpr(lc.elt.*, param_name)) return true;
            for (lc.generators) |gen| {
                if (isParamComparedToStringInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParamComparedToStringInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .dictcomp => |dc| {
            if (isParamComparedToStringInExpr(dc.key.*, param_name)) return true;
            if (isParamComparedToStringInExpr(dc.value.*, param_name)) return true;
            for (dc.generators) |gen| {
                if (isParamComparedToStringInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParamComparedToStringInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .genexp => |ge| {
            if (isParamComparedToStringInExpr(ge.elt.*, param_name)) return true;
            for (ge.generators) |gen| {
                if (isParamComparedToStringInExpr(gen.iter.*, param_name)) return true;
                for (gen.ifs) |cond| if (isParamComparedToStringInExpr(cond, param_name)) return true;
            }
            return false;
        },
        .starred => |st| isParamComparedToStringInExpr(st.value.*, param_name),
        .attribute => |attr| isParamComparedToStringInExpr(attr.value.*, param_name),
        else => false,
    };
}

/// Check if a parameter is used in isinstance() or similar type-checking call
pub fn isParameterUsedInTypeCheck(body: []const ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .return_stmt => |ret| {
                if (ret.value) |value| {
                    if (isTypeCheckCall(value.*, param_name)) return true;
                }
            },
            .for_stmt => |for_s| {
                for (for_s.body) |body_stmt| {
                    if (body_stmt == .if_stmt) {
                        if (isTypeCheckCall(body_stmt.if_stmt.condition.*, param_name)) return true;
                    }
                }
                if (for_s.orelse_body) |orelse_body| {
                    if (isParameterUsedInTypeCheck(orelse_body, param_name)) return true;
                }
            },
            .if_stmt => |if_s| {
                if (isTypeCheckCall(if_s.condition.*, param_name)) return true;
                if (isParameterUsedInTypeCheck(if_s.body, param_name)) return true;
                if (isParameterUsedInTypeCheck(if_s.else_body, param_name)) return true;
            },
            .while_stmt => |while_s| {
                if (isTypeCheckCall(while_s.condition.*, param_name)) return true;
                if (isParameterUsedInTypeCheck(while_s.body, param_name)) return true;
                if (while_s.orelse_body) |orelse_body| {
                    if (isParameterUsedInTypeCheck(orelse_body, param_name)) return true;
                }
            },
            .try_stmt => |try_stmt| {
                if (isParameterUsedInTypeCheck(try_stmt.body, param_name)) return true;
                for (try_stmt.handlers) |handler| {
                    if (isParameterUsedInTypeCheck(handler.body, param_name)) return true;
                }
                if (isParameterUsedInTypeCheck(try_stmt.else_body, param_name)) return true;
                if (isParameterUsedInTypeCheck(try_stmt.finalbody, param_name)) return true;
            },
            .with_stmt => |with_stmt| {
                if (isParameterUsedInTypeCheck(with_stmt.body, param_name)) return true;
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    if (isParameterUsedInTypeCheck(case.body, param_name)) return true;
                }
            },
            .function_def => |func_def| {
                if (isParameterUsedInTypeCheck(func_def.body, param_name)) return true;
            },
            .class_def => |class_def| {
                if (isParameterUsedInTypeCheck(class_def.body, param_name)) return true;
            },
            .expr_stmt => |expr| {
                if (isTypeCheckCall(expr.value.*, param_name)) return true;
            },
            .assign => |assign| {
                if (isTypeCheckCall(assign.value.*, param_name)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn isTypeCheckCall(expr: ast.Node, param_name: []const u8) bool {
    if (expr == .call) {
        const func = expr.call.func.*;
        if (func == .name) {
            const func_name = func.name.id;
            if (std.mem.eql(u8, func_name, "isinstance")) {
                if (expr.call.args.len > 0 and expr.call.args[0] == .name) {
                    if (std.mem.eql(u8, expr.call.args[0].name.id, param_name)) {
                        return true;
                    }
                }
            }
        }
    }
    if (expr == .for_stmt) {
        for (expr.for_stmt.body) |body_stmt| {
            if (body_stmt == .if_stmt) {
                if (isTypeCheckCall(body_stmt.if_stmt.condition.*, param_name)) return true;
            }
        }
    }
    return false;
}

/// Check if a parameter is passed as an argument to another parameter that is called as a function
pub fn isParameterPassedToCallableParam(body: []const ast.Node, param_name: []const u8, func_params: []const ast.Arg) bool {
    var callable_params_buf: [32][]const u8 = undefined;
    var num_callable_params: usize = 0;

    for (func_params) |arg| {
        if (isParameterCalled(body, arg.name) and num_callable_params < callable_params_buf.len) {
            callable_params_buf[num_callable_params] = arg.name;
            num_callable_params += 1;
        }
    }

    for (body) |stmt| {
        if (isParamPassedToCallableInStmt(stmt, param_name, callable_params_buf[0..num_callable_params])) {
            return true;
        }
    }
    return false;
}

fn isParamPassedToCallableInStmt(stmt: ast.Node, param_name: []const u8, callable_params: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| isParamPassedToCallableInExpr(expr.value.*, param_name, callable_params),
        .assign => |assign| isParamPassedToCallableInExpr(assign.value.*, param_name, callable_params),
        .aug_assign => |aug| isParamPassedToCallableInExpr(aug.value.*, param_name, callable_params),
        .ann_assign => |ann| if (ann.value) |v| isParamPassedToCallableInExpr(v.*, param_name, callable_params) else false,
        .return_stmt => |ret| if (ret.value) |val| isParamPassedToCallableInExpr(val.*, param_name, callable_params) else false,
        .if_stmt => |if_stmt| {
            if (isParamPassedToCallableInExpr(if_stmt.condition.*, param_name, callable_params)) return true;
            for (if_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            for (if_stmt.else_body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isParamPassedToCallableInExpr(while_stmt.condition.*, param_name, callable_params)) return true;
            for (while_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            if (while_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            }
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isParamPassedToCallableInExpr(for_stmt.iter.*, param_name, callable_params)) return true;
            for (for_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            if (for_stmt.orelse_body) |orelse_body| {
                for (orelse_body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            }
            return false;
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            for (try_stmt.handlers) |handler| {
                for (handler.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            }
            for (try_stmt.else_body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            for (try_stmt.finalbody) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .with_stmt => |with_stmt| {
            if (isParamPassedToCallableInExpr(with_stmt.context_expr.*, param_name, callable_params)) return true;
            for (with_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            if (isParamPassedToCallableInExpr(match_stmt.subject.*, param_name, callable_params)) return true;
            for (match_stmt.cases) |case| {
                if (case.guard) |g| if (isParamPassedToCallableInExpr(g.*, param_name, callable_params)) return true;
                for (case.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            }
            return false;
        },
        .function_def => |func_def| {
            for (func_def.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .class_def => |class_def| {
            for (class_def.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .assert_stmt => |assert_stmt| {
            if (isParamPassedToCallableInExpr(assert_stmt.condition.*, param_name, callable_params)) return true;
            if (assert_stmt.msg) |m| if (isParamPassedToCallableInExpr(m.*, param_name, callable_params)) return true;
            return false;
        },
        else => false,
    };
}

fn isParamPassedToCallableInExpr(expr: ast.Node, param_name: []const u8, callable_params: []const []const u8) bool {
    return switch (expr) {
        .call => |call| {
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                for (callable_params) |cp| {
                    if (std.mem.eql(u8, func_name, cp)) {
                        for (call.args) |arg| {
                            if (arg == .name and std.mem.eql(u8, arg.name.id, param_name)) {
                                return true;
                            }
                        }
                    }
                }
            }
            for (call.args) |arg| {
                if (isParamPassedToCallableInExpr(arg, param_name, callable_params)) return true;
            }
            // Check keyword arguments
            for (call.keyword_args) |kw| {
                if (isParamPassedToCallableInExpr(kw.value, param_name, callable_params)) return true;
            }
            return false;
        },
        .binop => |binop| {
            if (isParamPassedToCallableInExpr(binop.left.*, param_name, callable_params)) return true;
            if (isParamPassedToCallableInExpr(binop.right.*, param_name, callable_params)) return true;
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                if (isParamPassedToCallableInExpr(elt, param_name, callable_params)) return true;
            }
            return false;
        },
        .unaryop => |u| isParamPassedToCallableInExpr(u.operand.*, param_name, callable_params),
        .boolop => |b| {
            for (b.values) |v| {
                if (isParamPassedToCallableInExpr(v, param_name, callable_params)) return true;
            }
            return false;
        },
        .compare => |comp| {
            if (isParamPassedToCallableInExpr(comp.left.*, param_name, callable_params)) return true;
            for (comp.comparators) |c| {
                if (isParamPassedToCallableInExpr(c, param_name, callable_params)) return true;
            }
            return false;
        },
        .if_expr => |ie| {
            if (isParamPassedToCallableInExpr(ie.condition.*, param_name, callable_params)) return true;
            if (isParamPassedToCallableInExpr(ie.body.*, param_name, callable_params)) return true;
            if (isParamPassedToCallableInExpr(ie.orelse_value.*, param_name, callable_params)) return true;
            return false;
        },
        .subscript => |sub| {
            if (isParamPassedToCallableInExpr(sub.value.*, param_name, callable_params)) return true;
            return switch (sub.slice) {
                .index => |idx| isParamPassedToCallableInExpr(idx.*, param_name, callable_params),
                .slice => |sr| {
                    if (sr.lower) |l| if (isParamPassedToCallableInExpr(l.*, param_name, callable_params)) return true;
                    if (sr.upper) |up| if (isParamPassedToCallableInExpr(up.*, param_name, callable_params)) return true;
                    if (sr.step) |s| if (isParamPassedToCallableInExpr(s.*, param_name, callable_params)) return true;
                    return false;
                },
            };
        },
        .list => |lst| {
            for (lst.elts) |e| {
                if (isParamPassedToCallableInExpr(e, param_name, callable_params)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (isParamPassedToCallableInExpr(k, param_name, callable_params)) return true;
            }
            for (d.values) |v| {
                if (isParamPassedToCallableInExpr(v, param_name, callable_params)) return true;
            }
            return false;
        },
        .fstring => |fs| {
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| if (isParamPassedToCallableInExpr(e.node.*, param_name, callable_params)) return true,
                    .format_expr => |fe| if (isParamPassedToCallableInExpr(fe.expr.*, param_name, callable_params)) return true,
                    .conv_expr => |ce| if (isParamPassedToCallableInExpr(ce.expr.*, param_name, callable_params)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .lambda => |lam| isParamPassedToCallableInExpr(lam.body.*, param_name, callable_params),
        .listcomp => |lc| {
            if (isParamPassedToCallableInExpr(lc.elt.*, param_name, callable_params)) return true;
            for (lc.generators) |gen| {
                if (isParamPassedToCallableInExpr(gen.iter.*, param_name, callable_params)) return true;
                for (gen.ifs) |cond| if (isParamPassedToCallableInExpr(cond, param_name, callable_params)) return true;
            }
            return false;
        },
        .dictcomp => |dc| {
            if (isParamPassedToCallableInExpr(dc.key.*, param_name, callable_params)) return true;
            if (isParamPassedToCallableInExpr(dc.value.*, param_name, callable_params)) return true;
            for (dc.generators) |gen| {
                if (isParamPassedToCallableInExpr(gen.iter.*, param_name, callable_params)) return true;
                for (gen.ifs) |cond| if (isParamPassedToCallableInExpr(cond, param_name, callable_params)) return true;
            }
            return false;
        },
        .genexp => |ge| {
            if (isParamPassedToCallableInExpr(ge.elt.*, param_name, callable_params)) return true;
            for (ge.generators) |gen| {
                if (isParamPassedToCallableInExpr(gen.iter.*, param_name, callable_params)) return true;
                for (gen.ifs) |cond| if (isParamPassedToCallableInExpr(cond, param_name, callable_params)) return true;
            }
            return false;
        },
        .starred => |st| isParamPassedToCallableInExpr(st.value.*, param_name, callable_params),
        .attribute => |attr| isParamPassedToCallableInExpr(attr.value.*, param_name, callable_params),
        else => false,
    };
}

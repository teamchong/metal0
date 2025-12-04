/// Parameter usage analysis for decorator and higher-order function detection
/// Uses shared variable_usage module for core AST traversal
const std = @import("std");
const ast = @import("ast");
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
            return false;
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| if (isParameterCalledInStmt(s, param_name)) return true;
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
            },
            .if_stmt => |if_stmt| {
                if (isParameterUsedAsIterator(if_stmt.body, param_name)) return true;
                if (isParameterUsedAsIterator(if_stmt.else_body, param_name)) return true;
            },
            .while_stmt => |while_stmt| {
                if (isParameterUsedAsIterator(while_stmt.body, param_name)) return true;
            },
            .function_def => |func_def| {
                if (isParameterUsedAsIterator(func_def.body, param_name)) return true;
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
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isFirstParamUsedNonUnittestInExpr(for_stmt.iter.*, name)) return true;
            if (isFirstParamUsedNonUnittest(for_stmt.body, name)) return true;
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
                        return false;
                    }
                }
            }
            if (isFirstParamUsedNonUnittestInExpr(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (isFirstParamUsedNonUnittestInExpr(arg, name)) return true;
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
                else => {},
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
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isParameterComparedToString(for_stmt.body, param_name)) return true;
            return false;
        },
        .return_stmt => |ret| {
            if (ret.value) |val| return isParamComparedToStringInExpr(val.*, param_name);
            return false;
        },
        .assign => |assign| isParamComparedToStringInExpr(assign.value.*, param_name),
        .expr_stmt => |expr| isParamComparedToStringInExpr(expr.value.*, param_name),
        .function_def => |func_def| isParameterComparedToString(func_def.body, param_name),
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
            },
            .if_stmt => |if_s| {
                if (isTypeCheckCall(if_s.condition.*, param_name)) return true;
                if (isParameterUsedInTypeCheck(if_s.body, param_name)) return true;
                if (isParameterUsedInTypeCheck(if_s.else_body, param_name)) return true;
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
        .return_stmt => |ret| if (ret.value) |val| isParamPassedToCallableInExpr(val.*, param_name, callable_params) else false,
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            for (if_stmt.else_body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            for (for_stmt.body) |s| if (isParamPassedToCallableInStmt(s, param_name, callable_params)) return true;
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
        else => false,
    };
}

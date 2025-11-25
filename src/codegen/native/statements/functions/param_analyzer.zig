/// Parameter usage analysis for decorator and higher-order function detection
const std = @import("std");
const ast = @import("../../../../ast.zig");

/// Check if a parameter is used inside a nested function (closure capture)
/// This detects params that are referenced by inner functions
pub fn isParameterUsedInNestedFunction(body: []ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .function_def => |func_def| {
                // Check if param_name is used in this nested function's body
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

/// Check if a name (variable/parameter) is used anywhere in the body
fn isNameUsedInBody(body: []ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameUsedInStmt(stmt, name)) return true;
    }
    return false;
}

fn isNameUsedInStmt(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| isNameUsedInExpr(expr.value.*, name),
        .assign => |assign| isNameUsedInExpr(assign.value.*, name),
        .return_stmt => |ret| if (ret.value) |val| isNameUsedInExpr(val.*, name) else false,
        .if_stmt => |if_stmt| {
            if (isNameUsedInExpr(if_stmt.condition.*, name)) return true;
            if (isNameUsedInBody(if_stmt.body, name)) return true;
            if (isNameUsedInBody(if_stmt.else_body, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isNameUsedInExpr(while_stmt.condition.*, name)) return true;
            if (isNameUsedInBody(while_stmt.body, name)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isNameUsedInBody(for_stmt.body, name)) return true;
            return false;
        },
        .function_def => |func_def| {
            // Recursively check nested functions
            if (isNameUsedInBody(func_def.body, name)) return true;
            return false;
        },
        else => false,
    };
}

fn isNameUsedInExpr(expr: ast.Node, name: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, name),
        .call => |call| {
            if (isNameUsedInExpr(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (isNameUsedInExpr(arg, name)) return true;
            }
            return false;
        },
        .binop => |binop| {
            return isNameUsedInExpr(binop.left.*, name) or
                isNameUsedInExpr(binop.right.*, name);
        },
        .compare => |comp| {
            if (isNameUsedInExpr(comp.left.*, name)) return true;
            for (comp.comparators) |c| {
                if (isNameUsedInExpr(c, name)) return true;
            }
            return false;
        },
        .unaryop => |unary| isNameUsedInExpr(unary.operand.*, name),
        .subscript => |sub| {
            if (isNameUsedInExpr(sub.value.*, name)) return true;
            // Check slice for index usage
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
        else => false,
    };
}

/// Check if a parameter is called as a function in the body
pub fn isParameterCalled(body: []ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        if (isParameterCalledInStmt(stmt, param_name)) return true;
    }
    return false;
}

/// Check if a parameter is used as a function (called or returned) - for decorators
pub fn isParameterUsedAsFunction(body: []ast.Node, param_name: []const u8) bool {
    // Check if parameter is called
    if (isParameterCalled(body, param_name)) return true;

    // Check if parameter is returned (decorator pattern)
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .name and std.mem.eql(u8, val.name.id, param_name)) {
                    return true;
                }
            }
        }
    }

    return false;
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
            // Check if function being called is the parameter
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, param_name)) {
                return true;
            }
            // Check arguments recursively
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

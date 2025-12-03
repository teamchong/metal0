/// Parameter usage analysis for decorator and higher-order function detection
const std = @import("std");
const ast = @import("ast");
const self_analyzer = @import("self_analyzer.zig");
const UnittestMethodNames = self_analyzer.unittest_assertion_methods;

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
pub fn isNameUsedInBody(body: []ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameUsedInStmt(stmt, name)) return true;
    }
    return false;
}

/// Check if a name is used in body EXCLUDING yield expressions.
/// For generators, yield becomes `// pass` so usages there don't survive codegen.
pub fn isNameUsedInBodyExcludingYield(body: []ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameUsedInStmtExcludingYield(stmt, name)) return true;
    }
    return false;
}

fn isNameUsedInStmtExcludingYield(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        // Skip yield statements entirely - they become `// pass` in codegen
        .yield_stmt, .yield_from_stmt => false,
        .expr_stmt => |expr| isNameUsedInExpr(expr.value.*, name),
        .assign => |assign| {
            for (assign.targets) |target| {
                if (isNameUsedInExpr(target, name)) return true;
            }
            return isNameUsedInExpr(assign.value.*, name);
        },
        .return_stmt => |ret| if (ret.value) |val| isNameUsedInExpr(val.*, name) else false,
        .if_stmt => |if_stmt| {
            if (isNameUsedInExpr(if_stmt.condition.*, name)) return true;
            if (isNameUsedInBodyExcludingYield(if_stmt.body, name)) return true;
            if (isNameUsedInBodyExcludingYield(if_stmt.else_body, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isNameUsedInExpr(while_stmt.condition.*, name)) return true;
            if (isNameUsedInBodyExcludingYield(while_stmt.body, name)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isNameUsedInExpr(for_stmt.iter.*, name)) return true;
            if (isNameUsedInBodyExcludingYield(for_stmt.body, name)) return true;
            return false;
        },
        .function_def => |func_def| isNameUsedInBodyExcludingYield(func_def.body, name),
        .with_stmt => |with_stmt| {
            if (isNameUsedInExpr(with_stmt.context_expr.*, name)) return true;
            if (isNameUsedInBodyExcludingYield(with_stmt.body, name)) return true;
            return false;
        },
        .try_stmt => |try_stmt| {
            if (isNameUsedInBodyExcludingYield(try_stmt.body, name)) return true;
            for (try_stmt.handlers) |handler| {
                if (isNameUsedInBodyExcludingYield(handler.body, name)) return true;
            }
            if (isNameUsedInBodyExcludingYield(try_stmt.else_body, name)) return true;
            if (isNameUsedInBodyExcludingYield(try_stmt.finalbody, name)) return true;
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

/// Check if a name is used in init body, excluding parent __init__ calls
/// Parent calls like Exception.__init__(self, ...) or super().__init__(...) are skipped
/// in code generation, so params only used there are effectively unused
pub fn isNameUsedInInitBody(body: []ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameUsedInStmtExcludingParentInit(stmt, name)) return true;
    }
    return false;
}

/// Check if a name is used in __new__ body in ways that translate to init() method
/// For __new__, only field assignments (self.x = param) should be considered as "used"
/// Return statements, calls to meta(), etc. don't translate to init() body
pub fn isNameUsedInNewForInit(body: []ast.Node, name: []const u8) bool {
    for (body) |stmt| {
        if (isNameUsedInNewStmtForInit(stmt, name)) return true;
    }
    return false;
}

fn isNameUsedInNewStmtForInit(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .assign => |assign| {
            // Only check field assignments (self.x = value)
            for (assign.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        // This is self.field = value - check if name is in value
                        return isNameUsedInExpr(assign.value.*, name);
                    }
                }
            }
            // For non-field assignments, check if this creates a local var used later for fields
            // (e.g., g = gcd(num, den); self.__num = num // g)
            // But for now, be conservative and skip non-field assignments
            return false;
        },
        .if_stmt => |if_stmt| {
            // Check nested field assignments
            if (isNameUsedInNewForInit(if_stmt.body, name)) return true;
            if (isNameUsedInNewForInit(if_stmt.else_body, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isNameUsedInNewForInit(while_stmt.body, name)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isNameUsedInNewForInit(for_stmt.body, name)) return true;
            return false;
        },
        // Don't consider return statements - they don't translate to init()
        // Don't consider expression statements (calls) - they don't translate to init()
        else => false,
    };
}

fn isNameUsedInStmtExcludingParentInit(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| {
            // Check if this is a parent __init__/__new__ call - if so, skip it
            if (isParentInitCall(expr.value.*)) return false;
            return isNameUsedInExpr(expr.value.*, name);
        },
        .assign => |assign| {
            // Check if this is `self = Parent.__new__(cls, ...)` - skip parent __new__ calls
            if (isParentInitCall(assign.value.*)) return false;
            // Check target first - if it's self.field = ..., params in value are used
            for (assign.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        // This is self.field = value - check if name is in value
                        return isNameUsedInExpr(assign.value.*, name);
                    }
                }
            }
            return isNameUsedInExpr(assign.value.*, name);
        },
        .return_stmt => |ret| if (ret.value) |val| isNameUsedInExpr(val.*, name) else false,
        .if_stmt => |if_stmt| {
            if (isNameUsedInExpr(if_stmt.condition.*, name)) return true;
            if (isNameUsedInInitBody(if_stmt.body, name)) return true;
            if (isNameUsedInInitBody(if_stmt.else_body, name)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (isNameUsedInExpr(while_stmt.condition.*, name)) return true;
            if (isNameUsedInInitBody(while_stmt.body, name)) return true;
            return false;
        },
        .for_stmt => |for_stmt| {
            if (isNameUsedInExpr(for_stmt.iter.*, name)) return true;
            if (isNameUsedInInitBody(for_stmt.body, name)) return true;
            return false;
        },
        else => false,
    };
}

/// Check if an expression is a parent __init__ or __new__ call
/// Matches: Parent.__init__(self, ...) or super().__init__(...) or str.__new__(cls, ...)
fn isParentInitCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;

    // Check for Parent.__init__ or Parent.__new__ pattern
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;
        if (std.mem.eql(u8, attr.attr, "__init__") or std.mem.eql(u8, attr.attr, "__new__")) {
            // Could be Parent.__init__ or super().__init__ or Parent.__new__
            return true;
        }
    }
    return false;
}

fn isNameUsedInStmt(stmt: ast.Node, name: []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |expr| isNameUsedInExpr(expr.value.*, name),
        .assign => |assign| {
            // Check targets for attribute assignments like: param.attr = value
            for (assign.targets) |target| {
                if (isNameUsedInExpr(target, name)) return true;
            }
            // Check the value
            return isNameUsedInExpr(assign.value.*, name);
        },
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
            // Check the iterator expression (e.g., `items` in `for x in items:`)
            if (isNameUsedInExpr(for_stmt.iter.*, name)) return true;
            if (isNameUsedInBody(for_stmt.body, name)) return true;
            return false;
        },
        .function_def => |func_def| {
            // Recursively check nested functions
            if (isNameUsedInBody(func_def.body, name)) return true;
            return false;
        },
        .with_stmt => |with_stmt| {
            // Check the context expression
            if (isNameUsedInExpr(with_stmt.context_expr.*, name)) return true;
            // Check the body of the with statement
            if (isNameUsedInBody(with_stmt.body, name)) return true;
            return false;
        },
        .try_stmt => |try_stmt| {
            // Check try body
            if (isNameUsedInBody(try_stmt.body, name)) return true;
            // Check exception handlers
            for (try_stmt.handlers) |handler| {
                if (isNameUsedInBody(handler.body, name)) return true;
            }
            // Check else body
            if (isNameUsedInBody(try_stmt.else_body, name)) return true;
            // Check finally body
            if (isNameUsedInBody(try_stmt.finalbody, name)) return true;
            return false;
        },
        .match_stmt => |match_stmt| {
            // Check subject expression
            if (isNameUsedInExpr(match_stmt.subject.*, name)) return true;
            // Check each case body and guard
            for (match_stmt.cases) |case| {
                if (case.guard) |guard| {
                    if (isNameUsedInExpr(guard.*, name)) return true;
                }
                if (isNameUsedInBody(case.body, name)) return true;
            }
            return false;
        },
        .yield_stmt => |yield_stmt| {
            // Check yield expression
            if (yield_stmt.value) |val| return isNameUsedInExpr(val.*, name);
            return false;
        },
        .yield_from_stmt => |yield_from| {
            // Check yield from iterable expression
            return isNameUsedInExpr(yield_from.value.*, name);
        },
        .aug_assign => |aug| {
            // Check augmented assignment (e.g., x += y)
            if (isNameUsedInExpr(aug.target.*, name)) return true;
            if (isNameUsedInExpr(aug.value.*, name)) return true;
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
            // Also check keyword arguments
            for (call.keyword_args) |kwarg| {
                if (isNameUsedInExpr(kwarg.value, name)) return true;
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
        .boolop => |boolop| {
            for (boolop.values) |val| {
                if (isNameUsedInExpr(val, name)) return true;
            }
            return false;
        },
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
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| {
                        if (isNameUsedInExpr(e.*, name)) return true;
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
            // Check if name is used in the element expression
            if (isNameUsedInExpr(lc.elt.*, name)) return true;
            // Check if name is used in generators (iterators and conditions)
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
        .starred => |starred| {
            // Handle *args unpacking - check the inner value (e.g., `args` in `*args`)
            return isNameUsedInExpr(starred.value.*, name);
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

/// Check if a parameter is used as a function (called somewhere in the body)
/// For decorators that return their parameter unchanged, the parameter still needs
/// to be called at some point for us to know it's a function type
pub fn isParameterUsedAsFunction(body: []ast.Node, param_name: []const u8) bool {
    // Only check if parameter is called as a function
    // "return param" alone doesn't mean param is a function - it could be any value
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

/// Check if a parameter is used as an iterator in a for loop or comprehension
/// This indicates the parameter should be a slice/list type, not a scalar
pub fn isParameterUsedAsIterator(body: []ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .for_stmt => |for_stmt| {
                // Check if the iterator is this parameter
                if (for_stmt.iter.* == .name and std.mem.eql(u8, for_stmt.iter.name.id, param_name)) {
                    return true;
                }
                // Recursively check nested statements
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

/// Check if param is used as iterator in an expression (e.g., list comprehension)
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


/// Check if first param is used in ways that don't get dispatched to unittest methods.
/// For test methods with non-"self" first param (e.g., test_self), calls like
/// test_self.assertEqual(...) get dispatched to runtime.unittest.assertEqual(...)
/// which doesn't actually use the Zig self parameter.
pub fn isFirstParamUsedNonUnittest(body: []ast.Node, param_name: []const u8) bool {
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
            // Check if this is a unittest method call: name.assertXxx(...)
            // If so, it doesn't count as using the param (gets dispatched to runtime.unittest)
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, name)) {
                    // This is `name.something(...)` - check if it's a unittest method
                    if (UnittestMethodNames.has(attr.attr)) {
                        // This is a unittest method call - doesn't use self
                        // But still check the arguments for other uses
                        for (call.args) |arg| {
                            if (isFirstParamUsedNonUnittestInExpr(arg, name)) return true;
                        }
                        return false;
                    }
                }
            }
            // Not a unittest method call - check normally
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
/// Pattern: if param == "string": ... or param != "string"
/// Such parameters should be typed as []const u8 (string type)
pub fn isParameterComparedToString(body: []ast.Node, param_name: []const u8) bool {
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
            // Check if left side is the parameter and compared to a string
            if (comp.left.* == .name and std.mem.eql(u8, comp.left.name.id, param_name)) {
                for (comp.comparators) |comparator| {
                    if (comparator == .constant and comparator.constant.value == .string) {
                        return true;
                    }
                }
            }
            // Check if any comparator is the parameter and left/other comparators are strings
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
/// Pattern: return isinstance(param, type) or isinstance(param, (type1, type2))
/// Such parameters should use anytype to accept any value for runtime type checking
pub fn isParameterUsedInTypeCheck(body: []ast.Node, param_name: []const u8) bool {
    for (body) |stmt| {
        switch (stmt) {
            .return_stmt => |ret| {
                if (ret.value) |value| {
                    if (isTypeCheckCall(value.*, param_name)) return true;
                }
            },
            .for_stmt => |for_s| {
                // Check for "for T in ...: if isinstance(x, T): return ..." pattern
                for (for_s.body) |body_stmt| {
                    if (body_stmt == .if_stmt) {
                        if (isTypeCheckCall(body_stmt.if_stmt.condition.*, param_name)) return true;
                    }
                }
            },
            .if_stmt => |if_s| {
                // Check for "if isinstance(x, T): ..." pattern
                if (isTypeCheckCall(if_s.condition.*, param_name)) return true;
                // Also check nested statements
                if (isParameterUsedInTypeCheck(if_s.body, param_name)) return true;
                if (isParameterUsedInTypeCheck(if_s.else_body, param_name)) return true;
            },
            else => {},
        }
    }
    return false;
}

/// Check if an expression is isinstance(param, ...) or a type-checking call on param
fn isTypeCheckCall(expr: ast.Node, param_name: []const u8) bool {
    if (expr == .call) {
        const func = expr.call.func.*;
        if (func == .name) {
            const func_name = func.name.id;
            // isinstance(x, type) is a type-checking call
            if (std.mem.eql(u8, func_name, "isinstance")) {
                if (expr.call.args.len > 0 and expr.call.args[0] == .name) {
                    if (std.mem.eql(u8, expr.call.args[0].name.id, param_name)) {
                        return true;
                    }
                }
            }
        }
    }
    // Check for "for T in ...: if isinstance(x, T): return True" pattern
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
/// Pattern: def foo(fxn, arg): fxn(arg) - here arg is passed to fxn which is a callable
/// These params should be anytype since they can be any type
pub fn isParameterPassedToCallableParam(body: []ast.Node, param_name: []const u8, func_params: []ast.Arg) bool {
    // First, find all parameters that are used as callables (functions)
    var callable_params_buf: [32][]const u8 = undefined;
    var num_callable_params: usize = 0;

    for (func_params) |arg| {
        if (isParameterCalled(body, arg.name) and num_callable_params < callable_params_buf.len) {
            callable_params_buf[num_callable_params] = arg.name;
            num_callable_params += 1;
        }
    }

    // Now check if param_name is passed to any of those callable params
    for (body) |stmt| {
        if (isParamPassedToCallableInStmt(stmt, param_name, callable_params_buf[0..num_callable_params])) {
            return true;
        }
    }
    return false;
}

fn isParamPassedToCallableInStmt(stmt: ast.Node, param_name: []const u8, callable_params: [][]const u8) bool {
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

fn isParamPassedToCallableInExpr(expr: ast.Node, param_name: []const u8, callable_params: [][]const u8) bool {
    return switch (expr) {
        .call => |call| {
            // Check if the function being called is one of our callable params
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                for (callable_params) |cp| {
                    if (std.mem.eql(u8, func_name, cp)) {
                        // This is a call to a callable param - check if our param is in args
                        for (call.args) |arg| {
                            if (arg == .name and std.mem.eql(u8, arg.name.id, param_name)) {
                                return true;
                            }
                        }
                    }
                }
            }
            // Also check nested calls
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

/// VM Fallback Variable Analysis
///
/// Pre-pass that scans function bodies to identify variables that will only be used
/// in VM fallback expressions. These variables need immediate discards emitted
/// because they appear "unused" in the generated Zig code (they're only referenced
/// inside eval() strings).
///
/// VM fallback patterns that trigger this:
/// - Type dunder method calls: complex.__eq__(f, x), operator.add(a, b)
/// - Calls on module attributes: module.Class.__method__(args)
///
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;

/// Known types that have dunder methods handled via VM fallback
const vm_fallback_types = [_][]const u8{
    "complex",
    "operator",
    "str",
    "int",
    "float",
    "list",
    "dict",
    "set",
    "tuple",
    "bytes",
    "frozenset",
};

/// Check if a name is a known VM fallback type
fn isVMFallbackType(name: []const u8) bool {
    for (vm_fallback_types) |t| {
        if (std.mem.eql(u8, name, t)) return true;
    }
    return false;
}

// Import isBuiltinName from nested_captures - single source of truth
const nested_captures = @import("nested_captures.zig");
const isBuiltinName = nested_captures.isBuiltinName;

/// Analyze a function body to collect variables used in VM fallback expressions
/// This must be called BEFORE generating any code so that vm_fallback_used_vars
/// is populated when assignments are generated
pub fn analyzeVMFallbackVars(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Clear previous function's data
    self.vm_fallback_used_vars.clearRetainingCapacity();

    // Scan all statements in the function body
    for (func.body) |stmt| {
        try scanStmtForVMFallback(self, stmt);
    }
}

/// Recursively scan a statement for VM fallback patterns
fn scanStmtForVMFallback(self: *NativeCodegen, stmt: ast.Node) !void {
    switch (stmt) {
        .expr_stmt => |expr| try scanExprForVMFallback(self, expr.value.*),
        .assign => |assign| {
            try scanExprForVMFallback(self, assign.value.*);
        },
        .aug_assign => |aug| {
            try scanExprForVMFallback(self, aug.value.*);
        },
        .if_stmt => |if_s| {
            try scanExprForVMFallback(self, if_s.condition.*);
            for (if_s.body) |s| try scanStmtForVMFallback(self, s);
            for (if_s.else_body) |s| try scanStmtForVMFallback(self, s);
        },
        .while_stmt => |while_s| {
            try scanExprForVMFallback(self, while_s.condition.*);
            for (while_s.body) |s| try scanStmtForVMFallback(self, s);
            if (while_s.orelse_body) |orelse_body| {
                for (orelse_body) |s| try scanStmtForVMFallback(self, s);
            }
        },
        .for_stmt => |for_s| {
            try scanExprForVMFallback(self, for_s.iter.*);
            for (for_s.body) |s| try scanStmtForVMFallback(self, s);
            if (for_s.orelse_body) |orelse_body| {
                for (orelse_body) |s| try scanStmtForVMFallback(self, s);
            }
        },
        .try_stmt => |try_s| {
            for (try_s.body) |s| try scanStmtForVMFallback(self, s);
            for (try_s.else_body) |s| try scanStmtForVMFallback(self, s);
            for (try_s.finalbody) |s| try scanStmtForVMFallback(self, s);
            for (try_s.handlers) |handler| {
                for (handler.body) |s| try scanStmtForVMFallback(self, s);
            }
        },
        .with_stmt => |with_s| {
            try scanExprForVMFallback(self, with_s.context_expr.*);
            for (with_s.body) |s| try scanStmtForVMFallback(self, s);
        },
        .return_stmt => |ret| {
            if (ret.value) |v| try scanExprForVMFallback(self, v.*);
        },
        .function_def => |func_def| {
            // Scan nested function bodies - they may contain VM fallback patterns
            // that reference variables from the enclosing scope
            for (func_def.body) |s| try scanStmtForVMFallback(self, s);
        },
        .class_def => {
            // Don't scan class definitions - they have their own scope
        },
        else => {},
    }
}

/// Scan an expression for VM fallback patterns
/// If found, collect all variable names from arguments
fn scanExprForVMFallback(self: *NativeCodegen, expr: ast.Node) !void {
    switch (expr) {
        .lambda => |lambda| {
            // Lambda expressions become VM fallbacks
            // Collect all captured variables (non-parameters used in body)
            try collectLambdaCapturedVars(self, lambda);
        },
        .call => |call| {
            // Check if this is a VM fallback pattern: type.__method__(args)
            if (isVMFallbackCall(call)) {
                // Collect all variable names from arguments
                for (call.args) |arg| {
                    try collectVarNamesFromExpr(self, arg);
                }
                for (call.keyword_args) |kw| {
                    try collectVarNamesFromExpr(self, kw.value);
                }
            }
            // Check for method calls on local variables: var.method(args)
            // These might become VM fallbacks if the variable has unknown/PyValue type
            // Collect the base variable name as potentially used in VM fallback
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (attr.value.* == .name) {
                    const base_name = attr.value.name.id;
                    // Skip Python builtins and keywords - these are handled natively
                    if (!isBuiltinName(base_name)) {
                        const name_copy = try self.arena.allocator().dupe(u8, base_name);
                        try self.vm_fallback_used_vars.put(name_copy, {});
                    }
                }
            }
            // Also recurse into the call for nested patterns (including lambda args)
            try scanExprForVMFallback(self, call.func.*);
            for (call.args) |arg| {
                try scanExprForVMFallback(self, arg);
            }
            for (call.keyword_args) |kw| {
                try scanExprForVMFallback(self, kw.value);
            }
        },
        .binop => |binop| {
            try scanExprForVMFallback(self, binop.left.*);
            try scanExprForVMFallback(self, binop.right.*);
        },
        .unaryop => |unary| {
            try scanExprForVMFallback(self, unary.operand.*);
        },
        .compare => |compare| {
            try scanExprForVMFallback(self, compare.left.*);
            for (compare.comparators) |comp| {
                try scanExprForVMFallback(self, comp);
            }
        },
        .if_expr => |if_e| {
            try scanExprForVMFallback(self, if_e.condition.*);
            try scanExprForVMFallback(self, if_e.body.*);
            try scanExprForVMFallback(self, if_e.orelse_value.*);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try scanExprForVMFallback(self, elem);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try scanExprForVMFallback(self, elem);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try scanExprForVMFallback(self, key);
            }
            for (dict.values) |v| {
                try scanExprForVMFallback(self, v);
            }
        },
        .set => |set_expr| {
            for (set_expr.elts) |elem| {
                try scanExprForVMFallback(self, elem);
            }
        },
        .subscript => |sub| {
            try scanExprForVMFallback(self, sub.value.*);
            switch (sub.slice) {
                .index => |idx| try scanExprForVMFallback(self, idx.*),
                .slice => |range| {
                    if (range.lower) |lower| try scanExprForVMFallback(self, lower.*);
                    if (range.upper) |upper| try scanExprForVMFallback(self, upper.*);
                    if (range.step) |step| try scanExprForVMFallback(self, step.*);
                },
            }
        },
        .attribute => |attr| {
            try scanExprForVMFallback(self, attr.value.*);
        },
        else => {},
    }
}

/// Check if a call expression is a VM fallback pattern
/// Pattern: type.__dunder__(args) where type is a known Python type
fn isVMFallbackCall(call: ast.Node.Call) bool {
    // Check if func is an attribute access like complex.__eq__
    if (call.func.* != .attribute) return false;
    const attr = call.func.attribute;

    // Check if the attribute is a dunder method
    if (attr.attr.len < 4) return false;
    if (!std.mem.startsWith(u8, attr.attr, "__")) return false;
    if (!std.mem.endsWith(u8, attr.attr, "__")) return false;

    // Check if the value is a known type name
    if (attr.value.* != .name) return false;
    const type_name = attr.value.name.id;

    return isVMFallbackType(type_name);
}

/// Check if an expression contains a lambda that will become a VM fallback
/// Lambda expressions that capture outer variables become VM fallbacks
fn exprContainsLambda(expr: ast.Node) bool {
    switch (expr) {
        .lambda => return true,
        .call => |call| {
            for (call.args) |arg| {
                if (exprContainsLambda(arg)) return true;
            }
            for (call.keyword_args) |kw| {
                if (exprContainsLambda(kw.value)) return true;
            }
            return false;
        },
        .list => |list| {
            for (list.elts) |elem| {
                if (exprContainsLambda(elem)) return true;
            }
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                if (exprContainsLambda(elem)) return true;
            }
            return false;
        },
        .if_expr => |if_e| {
            return exprContainsLambda(if_e.body.*) or exprContainsLambda(if_e.orelse_value.*);
        },
        else => return false,
    }
}

/// Collect captured variables from a lambda expression
/// Lambda parameters are local, but any other names are captured from outer scope
fn collectLambdaCapturedVars(self: *NativeCodegen, lambda: ast.Node.Lambda) !void {
    // Build set of lambda parameters
    var param_set = std.StringHashMap(void).init(self.allocator);
    defer param_set.deinit();
    for (lambda.args) |arg| {
        try param_set.put(arg.name, {});
    }

    // Collect variables from lambda body that are NOT parameters
    try collectNonParamVars(self, lambda.body.*, &param_set);
}

/// Collect variable names from an expression, excluding those in param_set
fn collectNonParamVars(self: *NativeCodegen, expr: ast.Node, param_set: *std.StringHashMap(void)) !void {
    switch (expr) {
        .name => |n| {
            // Skip lambda parameters
            if (param_set.contains(n.id)) return;
            // Skip Python builtins
            if (std.mem.eql(u8, n.id, "None") or std.mem.eql(u8, n.id, "True") or
                std.mem.eql(u8, n.id, "False") or std.mem.eql(u8, n.id, "self") or
                isVMFallbackType(n.id))
            {
                return;
            }
            // Track this captured variable
            const name_copy = try self.arena.allocator().dupe(u8, n.id);
            try self.vm_fallback_used_vars.put(name_copy, {});
        },
        .binop => |binop| {
            try collectNonParamVars(self, binop.left.*, param_set);
            try collectNonParamVars(self, binop.right.*, param_set);
        },
        .unaryop => |unary| {
            try collectNonParamVars(self, unary.operand.*, param_set);
        },
        .compare => |compare| {
            try collectNonParamVars(self, compare.left.*, param_set);
            for (compare.comparators) |comp| {
                try collectNonParamVars(self, comp, param_set);
            }
        },
        .call => |call| {
            try collectNonParamVars(self, call.func.*, param_set);
            for (call.args) |arg| {
                try collectNonParamVars(self, arg, param_set);
            }
            for (call.keyword_args) |kw| {
                try collectNonParamVars(self, kw.value, param_set);
            }
        },
        .attribute => |attr| {
            try collectNonParamVars(self, attr.value.*, param_set);
        },
        .subscript => |sub| {
            try collectNonParamVars(self, sub.value.*, param_set);
            switch (sub.slice) {
                .index => |idx| try collectNonParamVars(self, idx.*, param_set),
                .slice => |range| {
                    if (range.lower) |lower| try collectNonParamVars(self, lower.*, param_set);
                    if (range.upper) |upper| try collectNonParamVars(self, upper.*, param_set);
                    if (range.step) |step| try collectNonParamVars(self, step.*, param_set);
                },
            }
        },
        .if_expr => |if_e| {
            try collectNonParamVars(self, if_e.condition.*, param_set);
            try collectNonParamVars(self, if_e.body.*, param_set);
            try collectNonParamVars(self, if_e.orelse_value.*, param_set);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectNonParamVars(self, elem, param_set);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectNonParamVars(self, elem, param_set);
            }
        },
        else => {},
    }
}

/// Collect all variable names from an expression and add to vm_fallback_used_vars
fn collectVarNamesFromExpr(self: *NativeCodegen, expr: ast.Node) !void {
    switch (expr) {
        .name => |n| {
            // Skip Python builtins and keywords
            if (std.mem.eql(u8, n.id, "None") or std.mem.eql(u8, n.id, "True") or
                std.mem.eql(u8, n.id, "False") or std.mem.eql(u8, n.id, "self") or
                isVMFallbackType(n.id))
            {
                return;
            }
            // Track this variable
            const name_copy = try self.arena.allocator().dupe(u8, n.id);
            try self.vm_fallback_used_vars.put(name_copy, {});
        },
        .binop => |binop| {
            try collectVarNamesFromExpr(self, binop.left.*);
            try collectVarNamesFromExpr(self, binop.right.*);
        },
        .unaryop => |unary| {
            try collectVarNamesFromExpr(self, unary.operand.*);
        },
        .call => |call| {
            try collectVarNamesFromExpr(self, call.func.*);
            for (call.args) |arg| {
                try collectVarNamesFromExpr(self, arg);
            }
            for (call.keyword_args) |kw| {
                try collectVarNamesFromExpr(self, kw.value);
            }
        },
        .attribute => |attr| {
            try collectVarNamesFromExpr(self, attr.value.*);
        },
        .subscript => |sub| {
            try collectVarNamesFromExpr(self, sub.value.*);
            switch (sub.slice) {
                .index => |idx| try collectVarNamesFromExpr(self, idx.*),
                .slice => |range| {
                    if (range.lower) |lower| try collectVarNamesFromExpr(self, lower.*);
                    if (range.upper) |upper| try collectVarNamesFromExpr(self, upper.*);
                    if (range.step) |step| try collectVarNamesFromExpr(self, step.*);
                },
            }
        },
        .if_expr => |if_e| {
            try collectVarNamesFromExpr(self, if_e.condition.*);
            try collectVarNamesFromExpr(self, if_e.body.*);
            try collectVarNamesFromExpr(self, if_e.orelse_value.*);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try collectVarNamesFromExpr(self, elem);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try collectVarNamesFromExpr(self, elem);
            }
        },
        else => {},
    }
}

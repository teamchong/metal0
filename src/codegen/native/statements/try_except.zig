/// Try/except/finally statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("../../../utils/hashmap_helper.zig");

const FnvVoidMap = hashmap_helper.StringHashMap(void);

// Static string maps for DCE optimization
const BuiltinFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "print", {} },
    .{ "len", {} },
    .{ "range", {} },
    .{ "str", {} },
    .{ "int", {} },
    .{ "float", {} },
    .{ "bool", {} },
    .{ "list", {} },
    .{ "dict", {} },
    .{ "set", {} },
    .{ "tuple", {} },
});

const ExceptionMap = std.StaticStringMap([]const u8).initComptime(.{
    .{ "ZeroDivisionError", "ZeroDivisionError" },
    .{ "IndexError", "IndexError" },
    .{ "ValueError", "ValueError" },
    .{ "TypeError", "TypeError" },
    .{ "KeyError", "KeyError" },
});

/// Find all variable names referenced in an expression
fn findReferencedVarsInExpr(expr: ast.Node, vars: *FnvVoidMap, allocator: std.mem.Allocator) !void {
    switch (expr) {
        .name => |name_node| {
            try vars.put(name_node.id, {});
        },
        .attribute => |attr| {
            try findReferencedVarsInExpr(attr.value.*, vars, allocator);
        },
        .subscript => |sub| {
            try findReferencedVarsInExpr(sub.value.*, vars, allocator);
            if (sub.slice == .index) {
                try findReferencedVarsInExpr(sub.slice.index.*, vars, allocator);
            }
        },
        .call => |call| {
            try findReferencedVarsInExpr(call.func.*, vars, allocator);
            for (call.args) |arg| {
                try findReferencedVarsInExpr(arg, vars, allocator);
            }
        },
        .binop => |binop| {
            try findReferencedVarsInExpr(binop.left.*, vars, allocator);
            try findReferencedVarsInExpr(binop.right.*, vars, allocator);
        },
        .compare => |cmp| {
            try findReferencedVarsInExpr(cmp.left.*, vars, allocator);
            for (cmp.comparators) |comp| {
                try findReferencedVarsInExpr(comp, vars, allocator);
            }
        },
        .unaryop => |unary| {
            try findReferencedVarsInExpr(unary.operand.*, vars, allocator);
        },
        .list => |list| {
            for (list.elts) |elem| {
                try findReferencedVarsInExpr(elem, vars, allocator);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try findReferencedVarsInExpr(key, vars, allocator);
            }
            for (dict.values) |val| {
                try findReferencedVarsInExpr(val, vars, allocator);
            }
        },
        else => {},
    }
}

/// Find all variable names referenced in statements
fn findReferencedVarsInStmts(stmts: []ast.Node, vars: *FnvVoidMap, allocator: std.mem.Allocator) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                try findReferencedVarsInExpr(assign.value.*, vars, allocator);
            },
            .expr_stmt => |expr| {
                try findReferencedVarsInExpr(expr.value.*, vars, allocator);
            },
            .return_stmt => |ret| {
                if (ret.value) |val| {
                    try findReferencedVarsInExpr(val.*, vars, allocator);
                }
            },
            .if_stmt => |if_stmt| {
                try findReferencedVarsInExpr(if_stmt.condition.*, vars, allocator);
                try findReferencedVarsInStmts(if_stmt.body, vars, allocator);
                try findReferencedVarsInStmts(if_stmt.else_body, vars, allocator);
            },
            .while_stmt => |while_stmt| {
                try findReferencedVarsInExpr(while_stmt.condition.*, vars, allocator);
                try findReferencedVarsInStmts(while_stmt.body, vars, allocator);
            },
            .for_stmt => |for_stmt| {
                try findReferencedVarsInExpr(for_stmt.iter.*, vars, allocator);
                try findReferencedVarsInStmts(for_stmt.body, vars, allocator);
            },
            else => {},
        }
    }
}

pub fn genTry(self: *NativeCodegen, try_node: ast.Node.Try) CodegenError!void {
    // First pass: collect variables declared in try block that need hoisting
    var declared_vars = std.ArrayList([]const u8){};
    defer declared_vars.deinit(self.allocator);

    for (try_node.body) |stmt| {
        if (stmt == .assign) {
            // Assign has targets (plural) not target
            if (stmt.assign.targets.len > 0) {
                const target = stmt.assign.targets[0];
                if (target == .name) {
                    try declared_vars.append(self.allocator, target.name.id);
                }
            }
        }
    }

    // Wrap in block for defer scope
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Hoist variable declarations inside block (so they're accessible after try)
    for (declared_vars.items) |var_name| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "var ");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.appendSlice(self.allocator, ": i64 = undefined;\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});

        // Register type in type inferrer so print() knows the type
        try self.type_inferrer.var_types.put(var_name, .int);
    }

    // Generate finally as defer
    if (try_node.finalbody.len > 0) {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "defer {\n");
        self.indent();
        for (try_node.finalbody) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    // Generate try block with exception handling
    if (try_node.handlers.len > 0) {
        // Collect captured variables and declared variables
        var captured_vars = std.ArrayList([]const u8){};
        defer captured_vars.deinit(self.allocator);

        var declared_var_set = FnvVoidMap.init(self.allocator);
        defer declared_var_set.deinit();
        for (declared_vars.items) |var_name| {
            try declared_var_set.put(var_name, {});
        }

        // Find variables actually referenced in try block body (not just declared)
        var referenced_vars = FnvVoidMap.init(self.allocator);
        defer referenced_vars.deinit();
        try findReferencedVarsInStmts(try_node.body, &referenced_vars, self.allocator);

        // Capture only variables that are:
        // 1. Actually referenced in try block
        // 2. Not declared in try block (those are passed as pointers)
        // 3. Not built-in functions
        var ref_iter = referenced_vars.iterator();
        while (ref_iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if declared in try block (will be passed separately as pointer)
            if (declared_var_set.contains(name)) continue;

            // Skip built-in functions
            if (BuiltinFuncs.has(name)) continue;

            // Only capture if it exists in lifetimes (was declared before this point)
            if (self.semantic_info.lifetimes.contains(name)) {
                try captured_vars.append(self.allocator, name);
            }
        }

        // Create helper function
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const __TryHelper = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "fn run(");

        // Parameters - captured vars and declared vars (as pointers)
        var param_count: usize = 0;
        for (captured_vars.items) |var_name| {
            if (param_count > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, "p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ": anytype");
            param_count += 1;
        }
        for (declared_vars.items) |var_name| {
            if (param_count > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, "p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ": *i64");  // Pointer for mutable access
            param_count += 1;
        }

        try self.output.appendSlice(self.allocator, ") !void {\n");
        self.indent();

        // Create aliases for captured variables
        for (captured_vars.items) |var_name| {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "const __local_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ": @TypeOf(p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ") = p_");
            try self.output.appendSlice(self.allocator, var_name);
            try self.output.appendSlice(self.allocator, ";\n");

            // Add to rename map
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("__local_{s}", .{var_name});
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
        }

        // Create aliases for declared variables (dereference pointers)
        for (declared_vars.items) |var_name| {
            // Add to rename map to use dereferenced pointer
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("p_{s}.*", .{var_name});
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
        }

        // Generate try block body with renamed variables
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Clear rename map after generating body and free allocated strings
        for (captured_vars.items) |var_name| {
            if (self.var_renames.fetchSwapRemove(var_name)) |entry| {
                self.allocator.free(entry.value);
            }
        }
        for (declared_vars.items) |var_name| {
            if (self.var_renames.fetchSwapRemove(var_name)) |entry| {
                self.allocator.free(entry.value);
            }
        }

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");

        // Call helper with captured variables and pointers to declared variables
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "__TryHelper.run(");
        var call_param_count: usize = 0;
        for (captured_vars.items) |var_name| {
            if (call_param_count > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, var_name);
            call_param_count += 1;
        }
        for (declared_vars.items) |var_name| {
            if (call_param_count > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.output.appendSlice(self.allocator, "&");
            try self.output.appendSlice(self.allocator, var_name);
            call_param_count += 1;
        }

        // Check if we need to capture err (only if there are specific exception handlers)
        const has_specific_handler = blk: {
            for (try_node.handlers) |handler| {
                if (handler.type != null) break :blk true;
            }
            break :blk false;
        };

        if (has_specific_handler) {
            try self.output.appendSlice(self.allocator, ") catch |err| {\n");
        } else {
            try self.output.appendSlice(self.allocator, ") catch {\n");
        }
        self.indent();

        // Generate exception handlers
        var generated_handler = false;
        for (try_node.handlers, 0..) |handler, i| {
            if (i > 0) {
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "} else ");
            } else if (handler.type != null) {
                try self.emitIndent();
            }

            if (handler.type) |exc_type| {
                const zig_err = pythonExceptionToZigError(exc_type);
                try self.output.appendSlice(self.allocator, "if (err == error.");
                try self.output.appendSlice(self.allocator, zig_err);
                try self.output.appendSlice(self.allocator, ") {\n");
                self.indent();
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                generated_handler = true;
            } else {
                if (i > 0) {
                    try self.output.appendSlice(self.allocator, "{\n");
                } else {
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "{\n");
                }
                self.indent();
                // Don't need _ = err; anymore - Zig will auto-ignore unused err
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "}\n");
                generated_handler = true;
            }
        }

        if (generated_handler and try_node.handlers[try_node.handlers.len - 1].type != null) {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "} else {\n");
            self.indent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "return err;\n");
            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}\n");
        }

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");
    } else {
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // Clear hoisted variables from tracking after try block completes
    for (declared_vars.items) |var_name| {
        _ = self.hoisted_vars.swapRemove(var_name);
    }
}

fn pythonExceptionToZigError(exc_type: []const u8) []const u8 {
    return ExceptionMap.get(exc_type) orelse "GenericError";
}

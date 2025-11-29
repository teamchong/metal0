/// Try/except/finally statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

const FnvVoidMap = hashmap_helper.StringHashMap(void);

// Static string maps for DCE optimization
// Includes Python builtins, modules, and inline stdlib functions
const BuiltinFuncs = std.StaticStringMap(void).initComptime(.{
    // Python builtins
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
    .{ "input", {} },
    .{ "open", {} },
    .{ "abs", {} },
    .{ "max", {} },
    .{ "min", {} },
    .{ "sum", {} },
    .{ "sorted", {} },
    .{ "reversed", {} },
    .{ "enumerate", {} },
    .{ "zip", {} },
    .{ "map", {} },
    .{ "filter", {} },
    // Standard library modules (accessed via module.function())
    .{ "math", {} },
    .{ "json", {} },
    .{ "re", {} },
    .{ "hashlib", {} },
    .{ "random", {} },
    .{ "sys", {} },
    .{ "io", {} },
    .{ "os", {} },
    .{ "operator", {} },
    .{ "collections", {} },
    .{ "itertools", {} },
    .{ "functools", {} },
    .{ "time", {} },
    .{ "datetime", {} },
    .{ "pathlib", {} },
    .{ "urllib", {} },
    .{ "http", {} },
    .{ "asyncio", {} },
    // Inline stdlib functions (from inline-only modules)
    .{ "Counter", {} },  // collections.Counter
    .{ "chain", {} },    // itertools.chain
    .{ "product", {} },  // itertools.product
    .{ "combinations", {} }, // itertools.combinations
    .{ "permutations", {} }, // itertools.permutations
    .{ "randint", {} },  // random.randint
    .{ "choice", {} },   // random.choice
    .{ "shuffle", {} },  // random.shuffle
    .{ "seed", {} },     // random.seed
});

const ExceptionMap = std.StaticStringMap([]const u8).initComptime(.{
    .{ "ZeroDivisionError", "ZeroDivisionError" },
    .{ "IndexError", "IndexError" },
    .{ "ValueError", "ValueError" },
    .{ "TypeError", "TypeError" },
    .{ "KeyError", "KeyError" },
});

/// Check if a variable name is used in any statement within a list of statements
fn isNameUsedInStmts(stmts: []ast.Node, name: []const u8, allocator: std.mem.Allocator) bool {
    var vars = FnvVoidMap.init(allocator);
    defer vars.deinit();
    findReferencedVarsInStmts(stmts, &vars, allocator) catch return false;
    return vars.contains(name);
}

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

/// Find all variable names that are assigned (written) in statements
fn findWrittenVarsInStmts(stmts: []ast.Node, vars: *FnvVoidMap) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try vars.put(target.name.id, {});
                    }
                }
            },
            .aug_assign => |aug| {
                if (aug.target.* == .name) {
                    try vars.put(aug.target.name.id, {});
                }
            },
            .if_stmt => |if_stmt| {
                try findWrittenVarsInStmts(if_stmt.body, vars);
                try findWrittenVarsInStmts(if_stmt.else_body, vars);
            },
            .while_stmt => |while_stmt| {
                try findWrittenVarsInStmts(while_stmt.body, vars);
            },
            .for_stmt => |for_stmt| {
                try findWrittenVarsInStmts(for_stmt.body, vars);
            },
            else => {},
        }
    }
}

/// Find all variables locally declared within statements (for-loop targets only)
/// These are variables that should NOT be captured from outer scope
/// NOTE: We only track for-loop targets here, NOT assignment targets,
/// because assignments might be reassigning outer variables
fn findLocallyDeclaredVars(stmts: []ast.Node, vars: *FnvVoidMap) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            // NOTE: Don't include .assign targets here - assignments might be
            // reassigning variables from outer scope, not declaring new ones.
            // The declared_var_set handles first-time declarations separately.
            .for_stmt => |for_stmt| {
                // For-loop target variables are locally declared
                if (for_stmt.target.* == .name) {
                    try vars.put(for_stmt.target.name.id, {});
                } else if (for_stmt.target.* == .tuple) {
                    // Handle tuple unpacking: for a, b in items
                    for (for_stmt.target.tuple.elts) |elt| {
                        if (elt == .name) {
                            try vars.put(elt.name.id, {});
                        }
                    }
                }
                try findLocallyDeclaredVars(for_stmt.body, vars);
            },
            .if_stmt => |if_stmt| {
                try findLocallyDeclaredVars(if_stmt.body, vars);
                try findLocallyDeclaredVars(if_stmt.else_body, vars);
            },
            .while_stmt => |while_stmt| {
                try findLocallyDeclaredVars(while_stmt.body, vars);
            },
            else => {},
        }
    }
}

/// Find all variable names referenced in statements
fn findReferencedVarsInStmts(stmts: []ast.Node, vars: *FnvVoidMap, allocator: std.mem.Allocator) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Capture RHS (value being read)
                try findReferencedVarsInExpr(assign.value.*, vars, allocator);
                // Also capture LHS targets that are being written to (if they're names)
                for (assign.targets) |target| {
                    try findReferencedVarsInExpr(target, vars, allocator);
                }
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
    // Only hoist variables that aren't already declared in the current scope
    var declared_vars = std.ArrayList([]const u8){};
    defer declared_vars.deinit(self.allocator);

    for (try_node.body) |stmt| {
        if (stmt == .assign) {
            // Assign has targets (plural) not target
            if (stmt.assign.targets.len > 0) {
                const target = stmt.assign.targets[0];
                if (target == .name) {
                    const var_name = target.name.id;
                    // Only hoist if not already declared in scope or previously hoisted
                    if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
                        try declared_vars.append(self.allocator, var_name);
                    }
                }
            }
        }
    }

    // Hoist variable declarations BEFORE the block (so they're accessible after try)
    for (declared_vars.items) |var_name| {
        // Get the actual type from type inference (already computed)
        const var_type = self.type_inferrer.var_types.get(var_name);
        const zig_type = if (var_type) |vt| blk: {
            break :blk try self.nativeTypeToZigType(vt);
        } else "i64";
        defer if (var_type != null) self.allocator.free(zig_type);

        try self.emitIndent();
        try self.emit("var ");
        try self.emit(var_name);
        try self.emit(": ");
        try self.emit(zig_type);
        try self.emit(" = undefined;\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});
    }

    // Wrap in block for defer scope
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

    // Generate finally as defer
    if (try_node.finalbody.len > 0) {
        try self.emitIndent();
        try self.emit("defer {\n");
        self.indent();
        for (try_node.finalbody) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate try block with exception handling
    if (try_node.handlers.len > 0) {
        // Collect read-only captured variables (not written in try block)
        var read_only_vars = std.ArrayList([]const u8){};
        defer read_only_vars.deinit(self.allocator);

        // Collect written variables from outer scope (need pointers)
        var written_outer_vars = std.ArrayList([]const u8){};
        defer written_outer_vars.deinit(self.allocator);

        var declared_var_set = FnvVoidMap.init(self.allocator);
        defer declared_var_set.deinit();
        for (declared_vars.items) |var_name| {
            try declared_var_set.put(var_name, {});
        }

        // Find variables that are WRITTEN in try block body
        var written_vars = FnvVoidMap.init(self.allocator);
        defer written_vars.deinit();
        try findWrittenVarsInStmts(try_node.body, &written_vars);

        // Find variables actually referenced in try block body (not just declared)
        var referenced_vars = FnvVoidMap.init(self.allocator);
        defer referenced_vars.deinit();
        try findReferencedVarsInStmts(try_node.body, &referenced_vars, self.allocator);

        // Find locally declared variables (including for-loop targets) - these should NOT be captured
        var locally_declared = FnvVoidMap.init(self.allocator);
        defer locally_declared.deinit();
        try findLocallyDeclaredVars(try_node.body, &locally_declared);

        // Categorize variables:
        // 1. declared_vars: first declared in try block (hoisted, passed as pointer)
        // 2. written_outer_vars: from outer scope, written in try block (passed as pointer)
        // 3. read_only_vars: from outer scope, only read in try block (passed by value)
        var ref_iter = referenced_vars.iterator();
        while (ref_iter.next()) |entry| {
            const name = entry.key_ptr.*;

            // Skip if declared in try block (already in declared_vars)
            if (declared_var_set.contains(name)) continue;

            // Skip locally declared variables (for-loop targets, etc.) - they don't exist outside try
            if (locally_declared.contains(name)) continue;

            // Skip built-in functions
            if (BuiltinFuncs.has(name)) continue;

            // Skip user-defined functions (they're module-level, accessible directly)
            if (self.function_signatures.contains(name)) continue;
            if (self.functions_needing_allocator.contains(name)) continue;

            // Check if this variable is from outer scope
            // If the variable is written in the try block, it's definitely an outer variable
            // (otherwise it would be in declared_var_set or locally_declared)
            // If it's only read, we need to verify it exists in some tracking mechanism
            if (written_vars.contains(name)) {
                // Variable is written in try block and not locally declared - it's an outer variable
                try written_outer_vars.append(self.allocator, name);
            } else if (self.isDeclared(name) or self.semantic_info.lifetimes.contains(name) or self.type_inferrer.var_types.contains(name)) {
                // Variable is only read and we can verify it exists - capture as read-only
                try read_only_vars.append(self.allocator, name);
            }
        }

        // Create helper function with unique name to avoid shadowing in nested try blocks
        const helper_id = self.try_helper_counter;
        self.try_helper_counter += 1;

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __TryHelper_{d} = struct {{\n", .{helper_id});
        self.indent();
        try self.emitIndent();
        try self.emit("fn run(");

        // Parameters:
        // - read_only_vars: passed by value (anytype)
        // - written_outer_vars: passed as pointer (*i64)
        // - declared_vars: passed as pointer (*i64)
        var param_count: usize = 0;
        for (read_only_vars.items) |var_name| {
            if (param_count > 0) try self.emit(", ");
            try self.emit("p_");
            try self.emit(var_name);
            try self.emit(": anytype");
            param_count += 1;
        }
        for (written_outer_vars.items) |var_name| {
            if (param_count > 0) try self.emit(", ");
            try self.emit("p_");
            try self.emit(var_name);
            // Get actual type from type inference
            const var_type = self.type_inferrer.var_types.get(var_name);
            const zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);
            try self.emit(": *");
            try self.emit(zig_type); // Pointer for mutable access
            param_count += 1;
        }
        for (declared_vars.items) |var_name| {
            if (param_count > 0) try self.emit(", ");
            try self.emit("p_");
            try self.emit(var_name);
            // Get actual type from type inference
            const var_type = self.type_inferrer.var_types.get(var_name);
            const zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);
            try self.emit(": *");
            try self.emit(zig_type); // Pointer for mutable access
            param_count += 1;
        }

        try self.emit(") !void {\n");
        self.indent();

        // Create aliases for read-only captured variables (by value)
        for (read_only_vars.items) |var_name| {
            try self.emitIndent();
            try self.emit("const __local_");
            try self.emit(var_name);
            try self.emit(": @TypeOf(p_");
            try self.emit(var_name);
            try self.emit(") = p_");
            try self.emit(var_name);
            try self.emit(";\n");

            // Add to rename map
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("__local_{s}", .{var_name});
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(var_name, renamed);
        }

        // Create aliases for written outer variables (dereference pointers)
        for (written_outer_vars.items) |var_name| {
            // Add to rename map to use dereferenced pointer
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("p_{s}.*", .{var_name});
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
        for (read_only_vars.items) |var_name| {
            if (self.var_renames.fetchSwapRemove(var_name)) |entry| {
                self.allocator.free(entry.value);
            }
        }
        for (written_outer_vars.items) |var_name| {
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
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");

        // Call helper with:
        // - read_only_vars: by value
        // - written_outer_vars: as pointer (&)
        // - declared_vars: as pointer (&)
        try self.emitIndent();
        try self.output.writer(self.allocator).print("__TryHelper_{d}.run(", .{helper_id});
        var call_param_count: usize = 0;
        for (read_only_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            try self.emit(var_name);
            call_param_count += 1;
        }
        for (written_outer_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            try self.emit("&");
            try self.emit(var_name);
            call_param_count += 1;
        }
        for (declared_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            try self.emit("&");
            try self.emit(var_name);
            call_param_count += 1;
        }

        // Check if we need to capture err (if there are specific exception handlers OR exception var names)
        const needs_err_capture = blk: {
            for (try_node.handlers) |handler| {
                if (handler.type != null or handler.name != null) break :blk true;
            }
            break :blk false;
        };

        // Use unique error variable name to avoid shadowing in nested try blocks
        var err_var_buf: [32]u8 = undefined;
        const err_var = std.fmt.bufPrint(&err_var_buf, "__err_{d}", .{helper_id}) catch "__err";

        if (needs_err_capture) {
            try self.output.writer(self.allocator).print(") catch |{s}| {{\n", .{err_var});
        } else {
            try self.emit(") catch {\n");
        }
        self.indent();

        // Generate exception handlers
        var generated_handler = false;
        for (try_node.handlers, 0..) |handler, i| {
            if (i > 0) {
                try self.emitIndent();
                try self.emit("} else ");
            } else if (handler.type != null) {
                try self.emitIndent();
            }

            if (handler.type) |exc_type| {
                const zig_err = pythonExceptionToZigError(exc_type);
                try self.output.writer(self.allocator).print("if ({s} == error.", .{err_var});
                try self.emit(zig_err);
                try self.emit(") {\n");
                self.indent();
                // If handler has "as name", declare the exception variable as a string
                // But only if it's actually used in the handler body
                if (handler.name) |exc_name| {
                    if (isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        try self.emitIndent();
                        try self.emit("const ");
                        try self.emit(exc_name);
                        try self.output.writer(self.allocator).print(": []const u8 = @errorName({s});\n", .{err_var});
                    }
                }
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                generated_handler = true;
            } else {
                if (i > 0) {
                    try self.emit("{\n");
                } else {
                    try self.emitIndent();
                    try self.emit("{\n");
                }
                self.indent();
                // If handler has "as name", declare the exception variable as a string
                // But only if it's actually used in the handler body
                if (handler.name) |exc_name| {
                    if (isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        try self.emitIndent();
                        try self.emit("const ");
                        try self.emit(exc_name);
                        try self.output.writer(self.allocator).print(": []const u8 = @errorName({s});\n", .{err_var});
                    }
                }
                for (handler.body) |stmt| {
                    try self.generateStmt(stmt);
                }
                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");
                generated_handler = true;
            }
        }

        if (generated_handler and try_node.handlers[try_node.handlers.len - 1].type != null) {
            try self.emitIndent();
            try self.emit("} else {\n");
            self.indent();
            try self.emitIndent();
            try self.output.writer(self.allocator).print("return {s};\n", .{err_var});
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
    } else {
        for (try_node.body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // NOTE: Do NOT clear hoisted_vars here - keep tracking them for the entire function
    // so subsequent try blocks with the same variable name don't re-hoist them.
    // hoisted_vars will be cleared when the function ends or via function reset.
}

fn pythonExceptionToZigError(exc_type: []const u8) []const u8 {
    return ExceptionMap.get(exc_type) orelse "GenericError";
}

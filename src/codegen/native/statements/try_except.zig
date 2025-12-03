/// Try/except/finally statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");
const NativeType = @import("../../../analysis/native_types.zig").NativeType;
const param_analyzer = @import("functions/param_analyzer.zig");
const shared = @import("../shared_maps.zig");
const zig_keywords = @import("zig_keywords");

const FnvVoidMap = hashmap_helper.StringHashMap(void);

/// Check if a variable is captured by the current nested class
/// Uses current_class_captures which is set when entering nested class methods
fn isCapturedByCurrentClass(self: *NativeCodegen, var_name: []const u8) bool {
    const captured_vars = self.current_class_captures orelse return false;
    for (captured_vars) |captured| {
        if (std.mem.eql(u8, captured, var_name)) return true;
    }
    return false;
}

/// Detect try/except import pattern: try: import X except: X = None
/// Returns the module name if pattern matches and module is unavailable
fn detectOptionalImportPattern(try_node: ast.Node.Try, codegen: *NativeCodegen) ?[]const u8 {
    // Check if try body has exactly one import statement
    if (try_node.body.len != 1) return null;
    const try_stmt = try_node.body[0];
    if (try_stmt != .import_stmt) return null;
    const module_name = try_stmt.import_stmt.module;

    // Check if there's an except handler that assigns the same name to None
    for (try_node.handlers) |handler| {
        // Must be ImportError or bare except
        if (handler.type) |exc_type| {
            if (!std.mem.eql(u8, exc_type, "ImportError")) continue;
        }
        // Check handler body for: X = None
        for (handler.body) |stmt| {
            if (stmt == .assign) {
                if (stmt.assign.targets.len > 0 and stmt.assign.targets[0] == .name) {
                    const var_name = stmt.assign.targets[0].name.id;
                    // Check if assigning to the module name and value is None
                    if (std.mem.eql(u8, var_name, module_name)) {
                        const is_none = if (stmt.assign.value.* == .constant)
                            stmt.assign.value.constant.value == .none
                        else
                            false;
                        if (is_none) {
                            // Pattern matches! Check if module is available
                            if (codegen.import_registry.lookup(module_name) == null) {
                                // Module is not in registry - it's unavailable
                                return module_name;
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

// Use shared Python builtin names for DCE optimization
const BuiltinFuncs = shared.PythonBuiltinNames;

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
        .starred => |starred| {
            try findReferencedVarsInExpr(starred.value.*, vars, allocator);
        },
        .tuple => |tuple| {
            for (tuple.elts) |elem| {
                try findReferencedVarsInExpr(elem, vars, allocator);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                try findReferencedVarsInExpr(val, vars, allocator);
            }
        },
        .if_expr => |if_expr| {
            try findReferencedVarsInExpr(if_expr.condition.*, vars, allocator);
            try findReferencedVarsInExpr(if_expr.body.*, vars, allocator);
            try findReferencedVarsInExpr(if_expr.orelse_value.*, vars, allocator);
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
            .class_def => |class_def| {
                // Find variables referenced in class methods that come from outer scope
                // This handles cases like: for badval in [...]: class A: def f(self): return badval
                for (class_def.body) |class_stmt| {
                    if (class_stmt == .function_def) {
                        const method = class_stmt.function_def;
                        try findReferencedVarsInStmts(method.body, vars, allocator);
                    }
                }
            },
            .function_def => |func_def| {
                // Find variables referenced in nested function bodies
                try findReferencedVarsInStmts(func_def.body, vars, allocator);
            },
            .try_stmt => |try_stmt| {
                // Find variables referenced in try body and handlers
                try findReferencedVarsInStmts(try_stmt.body, vars, allocator);
                for (try_stmt.handlers) |handler| {
                    try findReferencedVarsInStmts(handler.body, vars, allocator);
                }
                try findReferencedVarsInStmts(try_stmt.else_body, vars, allocator);
                try findReferencedVarsInStmts(try_stmt.finalbody, vars, allocator);
            },
            else => {},
        }
    }
}

/// Check if statements contain break or continue (for try block control flow handling)
fn containsBreakOrContinue(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        switch (stmt) {
            .break_stmt => return true,
            .continue_stmt => return true,
            .if_stmt => |if_stmt| {
                if (containsBreakOrContinue(if_stmt.body)) return true;
                if (containsBreakOrContinue(if_stmt.else_body)) return true;
            },
            // Don't recurse into nested loops/functions - their break/continue is local
            else => {},
        }
    }
    return false;
}

pub fn genTry(self: *NativeCodegen, try_node: ast.Node.Try) CodegenError!void {
    // Detect optional import pattern: try: import X except: X = None
    // If module X is unavailable, mark it as skipped so functions using it are skipped
    if (detectOptionalImportPattern(try_node, self)) |unavailable_module| {
        try self.markSkippedModule(unavailable_module);
        // Generate: const X: ?*void = null; _ = X; (module is not available)
        // This allows code like `if X is None:` and `@unittest.skipIf(X is None, ...)`
        // The _ = X; suppresses "unused constant" warning
        try self.emitIndent();
        try self.emit("const ");
        try self.emit(unavailable_module);
        try self.emit(": ?*void = null; _ = ");
        try self.emit(unavailable_module);
        try self.emit("; // Optional import: module not available\n");
        return; // Skip generating the full try/except structure
    }

    // First pass: collect variables declared in try block AND except handlers that need hoisting
    // Only hoist variables that aren't already declared in the current scope
    // Store both name and the assignment expression value for type inference
    const HoistedVar = struct {
        name: []const u8,
        value: ast.Node, // The RHS expression for type inference
    };
    var declared_vars = std.ArrayList(HoistedVar){};
    defer declared_vars.deinit(self.allocator);

    // Helper to add variable if not already declared
    const addVarIfNeeded = struct {
        fn add(list: *std.ArrayList(HoistedVar), codegen: *NativeCodegen, var_name: []const u8, value: ast.Node) !void {
            // Only hoist if not already declared in scope or previously hoisted
            if (!codegen.isDeclared(var_name) and !codegen.hoisted_vars.contains(var_name)) {
                // Check if already in list
                for (list.items) |existing| {
                    if (std.mem.eql(u8, existing.name, var_name)) return;
                }
                try list.append(codegen.allocator, .{ .name = var_name, .value = value });
            }
        }
    }.add;

    // Recursively collect assigned variables from try body (including nested if/for/while)
    const collectAssignedVarsRecursive = struct {
        fn collect(stmts: []ast.Node, list: *std.ArrayList(HoistedVar), codegen: *NativeCodegen, addFn: anytype) !void {
            for (stmts) |stmt| {
                switch (stmt) {
                    .assign => |assign| {
                        for (assign.targets) |target| {
                            if (target == .name) {
                                try addFn(list, codegen, target.name.id, assign.value.*);
                            }
                        }
                    },
                    .if_stmt => |if_stmt| {
                        try collect(if_stmt.body, list, codegen, addFn);
                        try collect(if_stmt.else_body, list, codegen, addFn);
                    },
                    .for_stmt => |for_stmt| {
                        try collect(for_stmt.body, list, codegen, addFn);
                    },
                    .while_stmt => |while_stmt| {
                        try collect(while_stmt.body, list, codegen, addFn);
                    },
                    else => {},
                }
            }
        }
    }.collect;

    // Collect from try body recursively
    try collectAssignedVarsRecursive(try_node.body, &declared_vars, self, addVarIfNeeded);

    // CRITICAL: Also collect from except handlers!
    // Pattern: try: import X except: X = None
    // The X = None is in the except handler, needs hoisting too
    for (try_node.handlers) |handler| {
        try collectAssignedVarsRecursive(handler.body, &declared_vars, self, addVarIfNeeded);
    }

    // Hoist variable declarations BEFORE the block (so they're accessible after try)
    for (declared_vars.items) |hoisted| {
        const var_name = hoisted.name;

        // Infer type directly from the RHS expression - this is more accurate than
        // looking up by variable name which can confuse same-named vars in different methods
        const var_type = self.type_inferrer.inferExpr(hoisted.value) catch null;
        var zig_type = if (var_type) |vt| blk: {
            break :blk try self.nativeTypeToZigType(vt);
        } else "i64";
        defer if (var_type != null) self.allocator.free(zig_type);

        // If it's a class instance type, check if the class was renamed (e.g., duplicate S classes)
        if (var_type) |vt| {
            if (@as(std.meta.Tag(NativeType), vt) == .class_instance) {
                const class_name = vt.class_instance;
                if (self.var_renames.get(class_name)) |renamed| {
                    self.allocator.free(zig_type);
                    zig_type = try self.allocator.dupe(u8, renamed);
                }
            }
        }

        // Check if var_name would shadow a module-level import or function
        // If so, use a prefixed name to avoid Zig's "shadows declaration" error
        var actual_var_name = var_name;
        const shadows_module_level = self.imported_modules.contains(var_name) or self.module_level_funcs.contains(var_name);
        if (shadows_module_level and !self.var_renames.contains(var_name)) {
            const prefixed_name = try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ var_name, self.lambda_counter });
            self.lambda_counter += 1;
            try self.var_renames.put(var_name, prefixed_name);
            actual_var_name = prefixed_name;
        } else if (self.var_renames.get(var_name)) |renamed| {
            actual_var_name = renamed;
        }

        try self.emitIndent();
        try self.emit("var ");
        try self.emit(actual_var_name);
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
        // Set inside_defer flag so generated code uses 'catch {}' instead of 'try'
        const saved_inside_defer = self.inside_defer;
        self.inside_defer = true;
        defer self.inside_defer = saved_inside_defer;
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
        for (declared_vars.items) |hoisted| {
            try declared_var_set.put(hoisted.name, {});
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

            // Skip 'self' and '__self' - these are method parameters that may or may not
            // be named/available depending on self_analyzer.usesSelf(). If self is needed
            // in the try block, the method signature should already have it available.
            // Don't try to capture it as an outer variable.
            if (std.mem.eql(u8, name, "self") or std.mem.eql(u8, name, "__self")) continue;

            // Skip user-defined functions (they're module-level, accessible directly)
            if (self.function_signatures.contains(name)) continue;
            if (self.functions_needing_allocator.contains(name)) continue;

            // Skip imported modules (they're module-level constants, no need to capture)
            if (self.imported_modules.contains(name)) continue;

            // Check if this variable is from outer scope
            // If the variable is written in the try block, it's definitely an outer variable
            // (otherwise it would be in declared_var_set or locally_declared)
            // If it's only read, we need to verify it exists in some tracking mechanism
            if (written_vars.contains(name)) {
                // Variable is written in try block and not locally declared - it's an outer variable
                try written_outer_vars.append(self.allocator, name);
            } else if (self.isDeclared(name) or self.semantic_info.lifetimes.contains(name) or self.type_inferrer.var_types.contains(name) or self.nested_class_names.contains(name) or self.func_local_vars.contains(name)) {
                // Variable is only read and we can verify it exists - capture as read-only
                // Note: nested_class_names tracks classes defined inside methods (like for-loop bodies)
                // Note: func_local_vars tracks function-local variables declared before the try block
                try read_only_vars.append(self.allocator, name);
            }

            // If this is a nested class with captured variables, also capture those variables
            // Example: class A captures badval, try block uses A() -> need to pass badval too
            if (self.nested_class_captures.get(name)) |captured_vars| {
                for (captured_vars) |cap_var| {
                    // Add captured var if not already tracked and exists in outer scope
                    var already_tracked = false;
                    for (read_only_vars.items) |existing| {
                        if (std.mem.eql(u8, existing, cap_var)) {
                            already_tracked = true;
                            break;
                        }
                    }
                    if (!already_tracked) {
                        for (written_outer_vars.items) |existing| {
                            if (std.mem.eql(u8, existing, cap_var)) {
                                already_tracked = true;
                                break;
                            }
                        }
                    }
                    if (!already_tracked and (self.isDeclared(cap_var) or self.semantic_info.lifetimes.contains(cap_var) or self.type_inferrer.var_types.contains(cap_var) or self.func_local_vars.contains(cap_var))) {
                        try read_only_vars.append(self.allocator, cap_var);
                    }
                }
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
            // Get actual type from type inference (local scope first, then global)
            const var_type = self.getVarType(var_name);
            var zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);
            // Check for class renames (e.g., Rat -> metal0_main.Rat)
            if (var_type) |vt| {
                if (@as(std.meta.Tag(NativeType), vt) == .class_instance) {
                    if (self.var_renames.get(vt.class_instance)) |renamed| {
                        self.allocator.free(zig_type);
                        zig_type = try self.allocator.dupe(u8, renamed);
                    }
                }
            }
            try self.emit(": *");
            try self.emit(zig_type); // Pointer for mutable access
            param_count += 1;
        }
        for (declared_vars.items) |hoisted| {
            if (param_count > 0) try self.emit(", ");
            try self.emit("p_");
            try self.emit(hoisted.name);
            // Infer type directly from the RHS expression
            const var_type = self.type_inferrer.inferExpr(hoisted.value) catch null;
            var zig_type = if (var_type) |vt| blk: {
                break :blk try self.nativeTypeToZigType(vt);
            } else "i64";
            defer if (var_type != null) self.allocator.free(zig_type);
            // Check for class renames
            if (var_type) |vt| {
                if (@as(std.meta.Tag(NativeType), vt) == .class_instance) {
                    if (self.var_renames.get(vt.class_instance)) |renamed| {
                        self.allocator.free(zig_type);
                        zig_type = try self.allocator.dupe(u8, renamed);
                    }
                }
            }
            try self.emit(": *");
            try self.emit(zig_type); // Pointer for mutable access
            param_count += 1;
        }

        try self.emit(") !void {\n");
        self.indent();

        // Save any existing renames for read_only_vars before overwriting
        // (e.g., function param `x` -> `__p_x_0` needs to be restored after try block)
        var saved_read_only_renames = std.ArrayList(struct { name: []const u8, rename: []const u8 }){};
        defer saved_read_only_renames.deinit(self.allocator);
        for (read_only_vars.items) |var_name| {
            if (self.var_renames.get(var_name)) |existing_rename| {
                try saved_read_only_renames.append(self.allocator, .{
                    .name = var_name,
                    .rename = try self.allocator.dupe(u8, existing_rename),
                });
            }
        }

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

            // Always emit discard using runtime.discard() to prevent "unused local constant"
            // errors while avoiding "pointless discard of local constant" issues
            try self.emitIndent();
            try self.emit("runtime.discard(__local_");
            try self.emit(var_name);
            try self.emit(");\n");

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

        // Save any existing import-shadowing renames for hoisted vars before overwriting
        // (we'll restore them after generating the helper body)
        var saved_hoisted_renames = std.ArrayList(struct { name: []const u8, rename: []const u8 }){};
        defer saved_hoisted_renames.deinit(self.allocator);
        for (declared_vars.items) |hoisted| {
            if (self.var_renames.get(hoisted.name)) |existing_rename| {
                // Don't save if it's a p_* rename from a previous helper
                if (!std.mem.startsWith(u8, existing_rename, "p_")) {
                    try saved_hoisted_renames.append(self.allocator, .{
                        .name = hoisted.name,
                        .rename = try self.allocator.dupe(u8, existing_rename),
                    });
                }
            }
        }

        // Create aliases for declared variables (dereference pointers)
        // Also suppress unused parameter warnings since these vars may only be set in except block
        for (declared_vars.items) |hoisted| {
            // Check if variable is used in the try block body
            const is_used_in_try_body = param_analyzer.isNameUsedInBody(try_node.body, hoisted.name);

            // Suppress unused parameter warning only if var is NOT used in try block
            if (!is_used_in_try_body) {
                try self.emitIndent();
                try self.emit("_ = p_");
                try self.emit(hoisted.name);
                try self.emit(";\n");
            }

            // Add to rename map to use dereferenced pointer
            var buf = std.ArrayList(u8){};
            try buf.writer(self.allocator).print("p_{s}.*", .{hoisted.name});
            const renamed = try buf.toOwnedSlice(self.allocator);
            try self.var_renames.put(hoisted.name, renamed);
        }

        // Check if try body contains break/continue for special handling
        const has_break_continue = containsBreakOrContinue(try_node.body);
        const saved_break_helper_id = self.try_break_helper_id;
        if (has_break_continue) {
            self.try_break_helper_id = helper_id;
        }
        defer self.try_break_helper_id = saved_break_helper_id;

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
        for (declared_vars.items) |hoisted| {
            if (self.var_renames.fetchSwapRemove(hoisted.name)) |entry| {
                self.allocator.free(entry.value);
            }
        }

        // Restore import-shadowing renames for hoisted vars (needed for helper call)
        for (saved_hoisted_renames.items) |saved| {
            try self.var_renames.put(saved.name, saved.rename);
        }

        // Restore saved read_only_vars renames (e.g., function param x -> __p_x_0)
        // These are needed for the TryHelper call to use the correct parameter name
        for (saved_read_only_renames.items) |saved| {
            try self.var_renames.put(saved.name, saved.rename);
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
            // Check if variable has been renamed (e.g., function param x -> __p_x_0)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Check if this is a captured variable in the current nested class
            if (isCapturedByCurrentClass(self, var_name)) {
                // Access via __self.__captured_var.* for captured variables
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                try self.output.writer(self.allocator).print("{s}.__captured_{s}.*", .{ self_name, var_name });
            } else {
                try self.emit(actual_name);
            }
            call_param_count += 1;
        }
        for (written_outer_vars.items) |var_name| {
            if (call_param_count > 0) try self.emit(", ");
            // Check if variable has been renamed (e.g., function param a -> a__mut)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Check if this is a captured variable in the current nested class
            if (isCapturedByCurrentClass(self, var_name)) {
                // Access via __self.__captured_var for captured variables (already a pointer, no & needed)
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                try self.output.writer(self.allocator).print("{s}.__captured_{s}", .{ self_name, var_name });
            } else {
                try self.emit("&");
                try self.emit(actual_name);
            }
            call_param_count += 1;
        }
        for (declared_vars.items) |hoisted| {
            if (call_param_count > 0) try self.emit(", ");
            try self.emit("&");
            // Use renamed name if variable was renamed to avoid shadowing imports
            const actual_name = self.var_renames.get(hoisted.name) orelse hoisted.name;
            try self.emit(actual_name);
            call_param_count += 1;
        }

        // Check if we need to capture err (if there are specific exception handlers OR exception var names OR break/continue)
        const needs_err_capture = blk: {
            if (has_break_continue) break :blk true;
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

        // Handle break/continue from try body - must come first before exception handlers
        if (has_break_continue) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("if ({s} == error.BreakRequested) break;\n", .{err_var});
        }

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
                // Check if this variable was hoisted (already declared with var at outer scope)
                if (handler.name) |exc_name| {
                    if (isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        // Check if this name was already hoisted as a var
                        const is_hoisted = blk: {
                            for (declared_vars.items) |hoisted| {
                                if (std.mem.eql(u8, hoisted.name, exc_name)) break :blk true;
                            }
                            break :blk false;
                        };
                        try self.emitIndent();
                        if (is_hoisted) {
                            // Assign to the existing hoisted variable
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            try self.output.writer(self.allocator).print(" = @errorName({s});\n", .{err_var});
                        } else {
                            // Declare new const
                            try self.emit("const ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            try self.output.writer(self.allocator).print(": []const u8 = @errorName({s});\n", .{err_var});
                        }
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
                // Check if this variable was hoisted (already declared with var at outer scope)
                if (handler.name) |exc_name| {
                    if (isNameUsedInStmts(handler.body, exc_name, self.allocator)) {
                        // Check if this name was already hoisted as a var
                        const is_hoisted = blk: {
                            for (declared_vars.items) |hoisted| {
                                if (std.mem.eql(u8, hoisted.name, exc_name)) break :blk true;
                            }
                            break :blk false;
                        };
                        try self.emitIndent();
                        if (is_hoisted) {
                            // Assign to the existing hoisted variable
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            try self.output.writer(self.allocator).print(" = @errorName({s});\n", .{err_var});
                        } else {
                            // Declare new const
                            try self.emit("const ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), exc_name);
                            try self.output.writer(self.allocator).print(": []const u8 = @errorName({s});\n", .{err_var});
                        }
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

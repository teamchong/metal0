/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");
const typeHandling = @import("assign/type_handling.zig");
const valueGen = @import("assign/value_generation.zig");

/// Check if an expression references a skipped module (e.g., pytest.main())
/// This is used to skip code generation for calls to modules that weren't found
pub fn exprRefersToSkippedModule(self: *NativeCodegen, expr: ast.Node) bool {
    // Check calls: pytest.main() or pytest.skip()
    if (expr == .call) {
        const func = expr.call.func.*;
        // Check if func is module.method()
        if (func == .attribute) {
            const attr = func.attribute;
            // Check if base is a name (module name)
            if (attr.value.* == .name) {
                const module_name = attr.value.name.id;
                if (self.isSkippedModule(module_name)) {
                    return true;
                }
            }
        }
        // Check if func is a skipped module function directly: pytest()
        if (func == .name) {
            const func_name = func.name.id;
            if (self.isSkippedModule(func_name)) {
                return true;
            }
            // Also check if it's a skipped user function: run_code()
            if (self.isSkippedFunction(func_name)) {
                return true;
            }
        }
    }
    // Check attribute access: pytest.mark.skip
    if (expr == .attribute) {
        var current = expr.attribute.value;
        while (true) {
            if (current.* == .name) {
                if (self.isSkippedModule(current.name.id)) {
                    return true;
                }
                break;
            } else if (current.* == .attribute) {
                current = current.attribute.value;
            } else {
                break;
            }
        }
    }
    // Check name references: just using pytest as a variable
    if (expr == .name) {
        if (self.isSkippedModule(expr.name.id)) {
            return true;
        }
    }
    return false;
}

/// Check if a statement references a skipped module
pub fn stmtRefersToSkippedModule(self: *NativeCodegen, stmt: ast.Node) bool {
    switch (stmt) {
        .assign => |a| {
            return exprRefersToSkippedModule(self, a.value.*);
        },
        .ann_assign => |ann| {
            if (ann.value) |val| {
                return exprRefersToSkippedModule(self, val.*);
            }
            return false;
        },
        .expr_stmt => |expr| {
            return exprRefersToSkippedModule(self, expr.value.*);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                return exprRefersToSkippedModule(self, val.*);
            }
            return false;
        },
        .if_stmt => |if_s| {
            // Check condition and all branches
            if (exprRefersToSkippedModule(self, if_s.condition.*)) return true;
            for (if_s.body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            for (if_s.else_body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            return false;
        },
        .for_stmt => |for_s| {
            if (exprRefersToSkippedModule(self, for_s.iter.*)) return true;
            for (for_s.body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            return false;
        },
        .while_stmt => |while_s| {
            if (exprRefersToSkippedModule(self, while_s.condition.*)) return true;
            for (while_s.body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            return false;
        },
        .try_stmt => |try_s| {
            for (try_s.body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            for (try_s.finalbody) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            return false;
        },
        .with_stmt => |with_s| {
            if (exprRefersToSkippedModule(self, with_s.context_expr.*)) return true;
            for (with_s.body) |s| {
                if (stmtRefersToSkippedModule(self, s)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Check if a function body references any skipped modules
pub fn functionBodyRefersToSkippedModule(self: *NativeCodegen, body: []const ast.Node) bool {
    for (body) |stmt| {
        if (stmtRefersToSkippedModule(self, stmt)) {
            return true;
        }
    }
    return false;
}

/// Generate annotated assignment statement (x: int = 5)
pub fn genAnnAssign(self: *NativeCodegen, ann_assign: ast.Node.AnnAssign) CodegenError!void {
    // If no value, just a declaration (x: int), skip for now
    if (ann_assign.value == null) return;

    // Convert to regular assignment and process
    const targets = try self.allocator.alloc(ast.Node, 1);
    targets[0] = ann_assign.target.*;

    const assign = ast.Node.Assign{
        .targets = targets,
        .value = ann_assign.value.?,
    };
    try genAssign(self, assign);

    // Free the temporary targets allocation
    self.allocator.free(targets);
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    // Skip assignments that reference skipped modules (e.g., result = subprocess.run(...))
    if (exprRefersToSkippedModule(self, assign.value.*)) {
        return;
    }

    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Handle tuple unpacking: a, b = (1, 2)
    // Note: Parser may represent tuple targets as either .tuple or .list
    if (assign.targets.len == 1 and assign.targets[0] == .tuple) {
        const target_tuple = assign.targets[0].tuple;
        try valueGen.genTupleUnpack(self, assign, target_tuple);
        return;
    }
    if (assign.targets.len == 1 and assign.targets[0] == .list) {
        // List target unpacking: [a, b] = x or a, b = x (parsed as list)
        const target_list = assign.targets[0].list;
        try valueGen.genListUnpack(self, assign, target_list);
        return;
    }

    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;

            // Special case: ellipsis assignment (x = ...)
            // Emit as explicit discard to avoid "unused variable" error
            if (assign.value.* == .ellipsis_literal) {
                try self.emitIndent();
                try self.emit("_ = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                return;
            }

            // Check collection types and allocation behavior
            const is_constant_array = typeHandling.isConstantArray(self, assign, var_name);
            const is_arraylist = typeHandling.isArrayList(self, assign, var_name);
            const is_listcomp = (assign.value.* == .listcomp);
            const is_dict = (assign.value.* == .dict);
            _ = assign.value.* == .dictcomp; // is_dictcomp - reserved for future use
            const is_allocated_string = typeHandling.isAllocatedString(self, assign.value.*);
            const is_mutable_class_instance = typeHandling.isMutableClassInstance(self, assign.value.*);

            // Check if this is first assignment or reassignment
            // Hoisted variables should skip declaration (already declared before try block)
            // Global variables should also skip declaration (they're declared in outer scope)
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const is_global = self.isGlobalVar(var_name);
            const is_first_assignment = !self.isDeclared(var_name) and !is_hoisted and !is_global;

            // Try compile-time evaluation FIRST
            if (self.comptime_evaluator.tryEval(assign.value.*)) |comptime_val| {
                // Only apply for simple types (no strings/lists that allocate during evaluation)
                // TODO: Strings and lists need proper arena allocation to avoid memory leaks
                const is_simple_type = switch (comptime_val) {
                    .int, .float, .bool => true,
                    .string, .list => false,
                };

                if (is_simple_type) {
                    // Check mutability BEFORE emitting
                    // Use isVarMutated() to check both module-level AND function-local mutations
                    const is_mutable = if (is_first_assignment)
                        self.isVarMutated(var_name)
                    else
                        false; // Reassignments don't declare

                    // Successfully evaluated at compile time!
                    try comptimeHelpers.emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);
                    if (is_first_assignment) {
                        try self.declareVar(var_name);
                    }

                    // If variable is used in eval string but nowhere else in actual code,
                    // emit _ = varname; to suppress Zig "unused" warning
                    if (self.isEvalStringVar(var_name)) {
                        try self.emitIndent();
                        try self.emit("_ = ");
                        try self.emit(var_name);
                        try self.emit(";\n");
                    }

                    return;
                }
                // Fall through to runtime codegen for strings/lists
                // Don't free - these are either AST-owned or will leak (TODO: arena)
            }

            try self.emitIndent();

            // For unused variables, discard with _ = expr; to avoid Zig errors
            // But PyObjects still need decref to free memory (e.g., json.loads)
            if (is_first_assignment and self.isVarUnused(var_name)) {
                if (value_type == .unknown) {
                    // PyObject: capture in block and decref immediately
                    // { const __unused = expr; runtime.decref(__unused, allocator); }
                    try self.emit("{ const __unused = ");
                    try self.genExpr(assign.value.*);
                    try self.emit("; runtime.decref(__unused, allocator); }\n");
                } else {
                    try self.emit("_ = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
                // Don't declare - variable doesn't exist
                return;
            }

            if (is_first_assignment) {
                // First assignment: emit var/const declaration with type annotation
                try valueGen.emitVarDeclaration(
                    self,
                    var_name,
                    value_type,
                    is_arraylist,
                    is_dict,
                    is_mutable_class_instance,
                    is_listcomp,
                );

                // Mark as declared
                try self.declareVar(var_name);

                // Track array slice vars
                const is_array_slice = typeHandling.isArraySlice(self, assign.value.*);
                if (is_array_slice) {
                    const var_name_copy = try self.allocator.dupe(u8, var_name);
                    try self.array_slice_vars.put(var_name_copy, {});
                }
            } else {
                // Reassignment: x = value (no var/const keyword!)
                // Use renamed version if in var_renames map (for exception handling)
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.emit(actual_name);
                try self.emit(" = ");
                // No type annotation on reassignment
            }

            // Special handling for string concatenation with nested operations
            // s1 + " " + s2 needs intermediate temps
            if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(assign.value.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(assign.value.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try valueGen.genStringConcat(self, assign, var_name, is_first_assignment);
                    return;
                }
            }

            // Special handling for list literals that will be mutated
            // Generate ArrayList initialization directly instead of fixed array
            if (is_arraylist and assign.value.* == .list) {
                const list = assign.value.list;
                try valueGen.genArrayListInit(self, var_name, list);

                // Add defer cleanup
                try deferCleanup.emitDeferCleanups(
                    self,
                    var_name,
                    is_first_assignment,
                    is_arraylist,
                    is_listcomp,
                    is_dict,
                    is_allocated_string,
                    assign.value.*,
                );
                return;
            }

            // Check if this is an async function call that needs auto-await
            const is_async_call = isAsyncFunctionCall(self, assign.value.*);

            if (is_async_call) {
                // Auto-await: wrap async call with scheduler init + wait + result extraction
                try self.emit("(blk: {\n");
                try self.emitIndent();
                // Initialize scheduler if needed (first async call)
                try self.emit("    if (!runtime.scheduler_initialized) {\n");
                try self.emitIndent();
                try self.emit("        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler = runtime.Scheduler.init(__global_allocator, __num_threads) catch unreachable;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler.start() catch unreachable;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler_initialized = true;\n");
                try self.emitIndent();
                try self.emit("    }\n");
                try self.emitIndent();
                try self.emit("    const __thread = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.emit("    runtime.scheduler.wait(__thread);\n");
                try self.emitIndent();
                try self.emit("    const __result = __thread.result orelse unreachable;\n");
                try self.emitIndent();
                try self.emit("    break :blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
                try self.emitIndent();
                try self.emit("});\n");
            } else {
                // Emit value normally
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
            }

            // Track variable metadata (ArrayList vars, closures, etc.)
            try valueGen.trackVariableMetadata(
                self,
                var_name,
                is_first_assignment,
                is_constant_array,
                typeHandling.isArraySlice(self, assign.value.*),
                assign,
            );

            // Add defer cleanup based on assignment type
            try deferCleanup.emitDeferCleanups(
                self,
                var_name,
                is_first_assignment,
                is_arraylist,
                is_listcomp,
                is_dict,
                is_allocated_string,
                assign.value.*,
            );
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value or obj.y = value)
            const attr = target.attribute;

            // Check if this is a dynamic attribute
            const is_dynamic = try isDynamicAttrAssign(self, attr);

            try self.emitIndent();
            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put() with type wrapping
                const dyn_value_type = try self.type_inferrer.inferExpr(assign.value.*);
                const py_value_tag = switch (dyn_value_type) {
                    .int => "int",
                    .float => "float",
                    .bool => "bool",
                    .string => "string",
                    else => "int", // Default fallback
                };

                try self.emit("try ");
                try self.genExpr(attr.value.*);
                try self.emitFmt(".__dict__.put(\"{s}\", runtime.PyValue{{ .{s} = ", .{ attr.attr, py_value_tag });
                try self.genExpr(assign.value.*);
                try self.emit(" })");
            } else {
                // Known attribute: direct assignment
                try self.genExpr(target);
                try self.emit(" = ");
                try self.genExpr(assign.value.*);
            }
            try self.emit(";\n");
        } else if (target == .subscript) {
            // Handle subscript assignment: self.routes[path] = handler, dict[key] = value
            const subscript = target.subscript;

            // Only handle index subscripts for now (not slices)
            if (subscript.slice == .index) {
                // Determine the container type to generate appropriate code
                const container_type = try self.type_inferrer.inferExpr(subscript.value.*);

                try self.emitIndent();

                if (container_type == .dict) {
                    // Dict assignment: dict.put(key, value)
                    try self.emit("try ");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".put(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", ");
                    try self.genExpr(assign.value.*);
                    try self.emit(");\n");
                } else if (container_type == .list) {
                    // List assignment: list.items[idx] = value
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                } else {
                    // Generic array/slice assignment: arr[idx] = value
                    try self.genExpr(subscript.value.*);
                    try self.emit("[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
            }
        }
    }
}

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

    // Handle subscript with slice augmented assignment: x[1:2] *= 2
    // This is a complex operation that modifies the list in place
    if (aug.target.* == .subscript and aug.target.subscript.slice == .slice) {
        // For slice augmented assignment, we need runtime support
        // For now, emit a comment placeholder - this feature is not yet supported
        try self.emit("// TODO: slice augmented assignment not yet supported\n");
        return;
    }

    // Emit target (variable name)
    try self.genExpr(aug.target.*);
    try self.emit(" = ");

    // Special handling for floor division and power
    if (aug.op == .FloorDiv) {
        try self.emit("@divFloor(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Pow) {
        try self.emit("std.math.pow(i64, ");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Mod) {
        try self.emit("@rem(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Handle bitwise shift operators separately due to RHS type casting
    if (aug.op == .LShift or aug.op == .RShift) {
        const shift_fn = if (aug.op == .LShift) "std.math.shl" else "std.math.shr";
        try self.emitFmt("{s}(i64, ", .{shift_fn});
        try self.genExpr(aug.target.*);
        try self.emit(", @as(u6, @intCast(");
        try self.genExpr(aug.value.*);
        try self.emit(")));\n");
        return;
    }

    // Regular operators: +=, -=, *=, /=, &=, |=, ^=
    // Handle matrix multiplication separately
    if (aug.op == .MatMul) {
        // MatMul: target @= value => target = numpy.matmulAuto(target, value)
        // Note: we already emitted "target = " above, so just emit the matmul call
        try self.emit("try numpy.matmulAuto(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(", allocator);\n");
        return;
    }

    try self.genExpr(aug.target.*);

    const op_str = switch (aug.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        else => " ? ",
    };
    try self.emit(op_str);

    try self.genExpr(aug.value.*);
    try self.emit(";\n");
}

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    // Skip expression statements that reference skipped modules (e.g., pytest.main())
    if (exprRefersToSkippedModule(self, expr)) {
        return;
    }

    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const genPrint = @import("misc.zig").genPrint;
            try genPrint(self, expr.call.args);
            return;
        }
    }

    // Special handling for unittest.main() - generates complete block with its own structure
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            const method_name = attr.attr;
            if (std.mem.eql(u8, obj_name, "unittest") and std.mem.eql(u8, method_name, "main")) {
                // unittest.main() generates its own complete output
                try self.genExpr(expr);
                return;
            }
        }
    }

    // Track if we added "_ = " prefix - if so, we ALWAYS need a semicolon
    var added_discard_prefix = false;

    // Discard string constants (docstrings) by assigning to _
    // Zig requires all non-void values to be used
    if (expr == .constant and expr.constant.value == .string) {
        try self.emit("_ = ");
        added_discard_prefix = true;
    }

    // Discard return values from function calls (Zig requires all non-void values to be used)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;

        // Builtin functions that return non-void values need _ = prefix
        const value_returning_builtins = [_][]const u8{
            "list", "dict", "set", "tuple", "frozenset",
            "str", "int", "float", "bool", "bytes", "bytearray",
            "range", "enumerate", "zip", "map", "filter", "sorted", "reversed",
            "len", "abs", "min", "max", "sum", "round", "pow",
            "ord", "chr", "hex", "oct", "bin",
            "type", "id", "hash", "repr", "ascii",
            "iter", "next", "slice", "object",
            "vars", "dir", "locals", "globals",
            "callable", "isinstance", "issubclass", "hasattr", "getattr",
            "format", "input",
        };

        var is_value_returning_builtin = false;
        for (value_returning_builtins) |builtin| {
            if (std.mem.eql(u8, func_name, builtin)) {
                is_value_returning_builtin = true;
                break;
            }
        }

        if (is_value_returning_builtin) {
            try self.emit("_ = ");
            added_discard_prefix = true;
        } else if (self.type_inferrer.func_return_types.get(func_name)) |return_type| {
            // Check if function returns non-void type
            // Skip void returns
            if (return_type != .unknown) {
                try self.emit("_ = ");
                added_discard_prefix = true;
            }
        }
    }

    const before_len = self.output.items.len;
    try self.genExpr(expr);

    // Check if generated code ends with a block statement (not struct initializers)
    const generated = self.output.items[before_len..];

    // Determine if we need a semicolon:
    // - If we added "_ = " prefix, we ALWAYS need a semicolon (it's an assignment)
    // - Struct initializers like "Type{}" need semicolons
    // - Statement blocks like "{ ... }" do NOT need semicolons
    // - Labeled blocks like "blk: { ... }" do NOT need semicolons
    var needs_semicolon = true;

    // If we added "_ = " prefix, it's an assignment that always needs semicolon
    if (!added_discard_prefix and generated.len > 0 and generated[generated.len - 1] == '}') {
        // Check for labeled blocks (e.g., "blk: {", "sub_0: {", "slice_1: {", "comp_2: {")
        // Pattern: identifier followed by colon and space then brace
        const is_labeled_block = blk: {
            // Check for common label patterns
            if (std.mem.indexOf(u8, generated, "blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "sub_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "slice_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "comp_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "dict_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "gen_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "idx_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "str_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "arr_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            // Generic check: look for pattern like "word_N: {" at the start
            if (generated.len >= 6) {
                // Check if starts with a label pattern (letters/underscore followed by digits, then ": {")
                var i: usize = 0;
                while (i < generated.len and (std.ascii.isAlphabetic(generated[i]) or generated[i] == '_')) : (i += 1) {}
                while (i < generated.len and std.ascii.isDigit(generated[i])) : (i += 1) {}
                if (i > 0 and i + 3 < generated.len and std.mem.eql(u8, generated[i .. i + 3], ": {")) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (is_labeled_block) {
            needs_semicolon = false;
        }
        // Check for anonymous statement blocks - starts with "{ " (not "Type{")
        // Statement blocks: "{ const x = ...; }"
        // Struct initializers: "Type{}" or "Type{ .field = value }"
        else if (generated.len >= 2) {
            // Find the first '{' and check what's before it
            if (std.mem.indexOf(u8, generated, "{ ")) |brace_pos| {
                if (brace_pos == 0) {
                    // Starts with "{ " - it's a statement block
                    needs_semicolon = false;
                }
            }
        }
    }

    if (needs_semicolon) {
        try self.emit(";\n");
    } else {
        try self.emit("\n");
    }
}

/// Check if attribute assignment is to a dynamic attribute
fn isDynamicAttrAssign(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Only check for class instance attributes (self.attr or obj.attr)
    if (attr.value.* != .name) return false;

    const obj_name = attr.value.name.id;

    // Get object type
    const obj_type = try self.type_inferrer.inferExpr(attr.value.*);

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if class has this field
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        // Check if field exists in class
        if (info.fields.get(attr.attr)) |_| {
            return false; // Known field
        }
    }

    // Check for special module attributes
    if (std.mem.eql(u8, obj_name, "sys")) {
        return false;
    }

    // Unknown field - dynamic attribute
    return true;
}

/// Check if expression is a call to an async function
fn isAsyncFunctionCall(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;

    // Only handle direct function calls (name), not method calls
    if (call.func.* != .name) return false;

    const func_name = call.func.name.id;
    return self.async_functions.contains(func_name);
}

// Comptime assignment functions moved to assign_comptime.zig

/// Miscellaneous statement code generation (return, import, assert, global, del, raise)
const std = @import("std");
const ast = @import("ast");
const zig_keywords = @import("zig_keywords");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const shared = @import("../shared_maps.zig");
const ExceptionTypes = shared.RuntimeExceptions;

// Re-export print statement generation
pub const genPrint = @import("print.zig").genPrint;

/// Check if a return value is a tail-recursive call to the current function
/// A tail call is: return func_name(args) where func_name == current function
fn isTailRecursiveCall(self: *NativeCodegen, value: ast.Node) ?ast.Node.Call {
    // Must be inside a function
    const current_func = self.current_function_name orelse return null;

    // Must be a call expression
    if (value != .call) return null;
    const call = value.call;

    // Function must be a simple name (not attribute/method call)
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Must be calling the current function
    if (!std.mem.eql(u8, func_name, current_func)) return null;

    return call;
}

/// Magic method return conversion info
const MagicMethodConversion = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Get conversion wrapper for magic method return values
/// Some dunder methods have fixed return types that require conversion
/// NOTE: __int__, __index__ don't need wrappers - they return i64 directly
fn getMagicMethodConversion(method_name: []const u8) ?MagicMethodConversion {
    const converters = std.StaticStringMap(MagicMethodConversion).initComptime(.{
        // Python 3: __bool__ must return exactly bool, not converted from other types
        .{ "__bool__", MagicMethodConversion{ .prefix = "runtime.validateBoolReturn(", .suffix = ")" } },
        // Use runtime.pyToInt for __len__/__hash__ to handle both int and PyValue
        .{ "__len__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__hash__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__float__", MagicMethodConversion{ .prefix = "runtime.toFloat(", .suffix = ")" } },
    });
    return converters.get(method_name);
}

/// Comparison magic methods that return bool
const ComparisonMagicMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__eq__", {} },
    .{ "__ne__", {} },
    .{ "__lt__", {} },
    .{ "__le__", {} },
    .{ "__gt__", {} },
    .{ "__ge__", {} },
});

/// Generate return statement with tail-call optimization
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    try self.emitIndent();

    if (ret.value) |value| {
        // Check if returning NotImplemented from a comparison method
        // In Python, comparison methods can return NotImplemented to signal fallback
        // But in our compiled code, these methods return bool, so convert to false
        if (value.* == .name and std.mem.eql(u8, value.name.id, "NotImplemented")) {
            if (self.current_function_name) |fn_name| {
                if (ComparisonMagicMethods.has(fn_name)) {
                    try self.emit("return false;\n");
                    return;
                }
            }
        }

        // Check if returning a pre-generated closure (e.g., return with_metaclass where with_metaclass is a nested function)
        if (value.* == .name) {
            const name = value.name.id;
            if (self.pending_closure_types.get(name)) |type_name| {
                // Return an instance of the pre-generated closure type
                try self.output.writer(self.allocator).print("return {s}{{}};\n", .{type_name});
                return;
            }
        }

        // Check for tail-recursive call
        if (isTailRecursiveCall(self, value.*)) |call| {
            // Emit: return @call(.always_tail, func_name, .{args})
            try self.emit("return @call(.always_tail, ");
            try self.emit(call.func.name.id);
            try self.emit(", .{");

            // Generate arguments
            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(arg);
            }

            try self.emit("});\n");
            return;
        }

        // Normal return - check if inside a magic method that needs conversion
        try self.emit("return ");

        // Check if returning self from a method (with either *@This() or *const @This())
        // When method signature returns !@This() and we return self,
        // we need: return __self.*; (dereference the pointer)
        // This applies to both mutable (*@This()) and immutable (*const @This()) methods
        const is_self_return = self.current_class_name != null and
            value.* == .name and
            std.mem.eql(u8, value.name.id, "self");
        // For methods that return self, always dereference when inside a nested method
        // (where self is renamed to __self) or when method_self_is_mutable
        const needs_self_deref = is_self_return and (self.method_self_is_mutable or self.method_nesting_depth > 0);

        // Check if we're inside a magic method that needs return value conversion
        const conversion = if (self.current_function_name) |fn_name|
            getMagicMethodConversion(fn_name)
        else
            null;

        if (needs_self_deref) {
            // For nested classes, return the pointer directly
            // since init() returns *@This() and methods returning self also return *@This()
            // For top-level classes, dereference to return @This() value
            const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
            const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
            if (current_class_is_nested) {
                // Nested class: return pointer directly
                try self.emit(self_name);
            } else {
                // Top-level class: dereference to get value
                try self.output.writer(self.allocator).print("{s}.*", .{self_name});
            }
        } else if (conversion) |conv| {
            try self.emit(conv.prefix);
            try self.genExpr(value.*);
            try self.emit(conv.suffix);
        } else {
            try self.genExpr(value.*);
        }
    } else {
        try self.emit("return ");
    }
    try self.emit(";\n");
}

/// Generate import statement: import module
/// For module-level imports, this is handled in PHASE 3
/// For local imports (inside functions), we need to generate const bindings
pub fn genImport(self: *NativeCodegen, import: ast.Node.Import) CodegenError!void {
    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3 of generator.zig
    // In module mode, indent_level == 1 means we're at struct level (still module-level)
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    const module_name = import.module;
    const alias = import.asname orelse module_name;

    // Look up in registry
    if (self.import_registry.lookup(module_name)) |info| {
        // Skip generating local import if the module is a well-known module
        // that's typically imported at module level - Python allows redundant imports
        // but Zig doesn't allow shadowing
        // Note: This is a heuristic - we skip stdlib modules since they're usually
        // imported at module level and would cause shadowing errors
        if (info.strategy == .zig_runtime) {
            return;
        }

        if (info.zig_import) |zig_import| {
            try self.emitIndent();
            try self.emit("const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias);
            try self.emit(" = ");
            try self.emit(zig_import);
            try self.emit(";\n");
        }
    }
}

/// Generate from-import statement: from module import names
/// Module-level imports are handled in PHASE 3 of generator.zig
/// Local imports (inside functions) need to generate const bindings
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    // Only generate for local imports (inside functions)
    // Module-level imports are handled in PHASE 3
    if (self.indent_level == 0) return;
    if (self.mode == .module and self.indent_level == 1) return;

    const module_name = import.module;

    // Look up in registry to get the Zig module path
    if (self.import_registry.lookup(module_name)) |info| {
        if (info.zig_import) |zig_import| {
            // Generate const bindings for each imported name
            // from random import getrandbits -> const getrandbits = runtime.random.getrandbits;
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                try self.emitIndent();
                try self.emit("const ");
                try self.emit(alias);
                try self.emit(" = ");
                try self.emit(zig_import);
                try self.emit(".");
                try self.emit(name);
                try self.emit(";\n");
            }
        } else {
            // Module uses inline codegen (e.g., random) - track symbols for dispatch
            // from random import getrandbits -> record "getrandbits" -> "random"
            for (import.names, 0..) |name, i| {
                const alias = if (i < import.asnames.len and import.asnames[i] != null)
                    import.asnames[i].?
                else
                    name;

                try self.local_from_imports.put(alias, module_name);
            }
        }
    }
}

/// Generate global statement
/// The global statement itself doesn't emit code - it just marks variables as global
/// so that subsequent assignments reference the outer scope variable instead of creating a new one
pub fn genGlobal(self: *NativeCodegen, global_node: ast.Node.GlobalStmt) CodegenError!void {
    // Mark each variable as global
    for (global_node.names) |name| {
        try self.markGlobalVar(name);
    }
    // No code emitted - this is a directive, not an executable statement
}

/// Generate del statement
/// In Python, del is mostly a memory hint. In AOT compilation, emit as comment.
pub fn genDel(self: *NativeCodegen, del_node: ast.Node.Del) CodegenError!void {
    _ = del_node; // del is a no-op in compiled code
    try self.emitIndent();
    try self.emit("// del statement (no-op in AOT)\n");
}

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!(condition)) { std.debug.panic("Assertion failed", .{}); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    try self.emitIndent();
    try self.emit("if (!(");
    try self.genExpr(assert_node.condition.*);
    try self.emit(")) {\n");

    self.indent();
    try self.emitIndent();

    if (assert_node.msg) |msg| {
        // assert x, "message" - use {any} to handle any type of message (string, int, etc.)
        try self.emit("std.debug.panic(\"AssertionError: {any}\", .{");
        try self.genExpr(msg.*);
        try self.emit("});\n");
    } else {
        // assert x
        try self.emit("std.debug.panic(\"AssertionError\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}


/// Check if with expression is a unittest context manager that should be skipped
/// Check if context manager is assertRaises or assertRaisesRegex (needs error handling)
/// Also handles tuples of context managers (e.g., with (assertRaises(), Stopwatch()) as ...)
fn isAssertRaisesContext(expr: ast.Node) bool {
    // Direct call to self.assertRaises or self.assertRaisesRegex
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name) {
                const obj_name = attr.value.name.id;
                if (std.mem.eql(u8, obj_name, "self")) {
                    const method_name = attr.attr;
                    if (std.mem.eql(u8, method_name, "assertRaises") or
                        std.mem.eql(u8, method_name, "assertRaisesRegex"))
                    {
                        return true;
                    }
                }
            }
        }
    }
    // Tuple of context managers - check if any element is assertRaises
    // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
    if (expr == .tuple) {
        for (expr.tuple.elts) |elt| {
            // Handle named expression (context manager as var)
            const actual_expr = if (elt == .named_expr) elt.named_expr.value.* else elt;
            if (isAssertRaisesContext(actual_expr)) {
                return true;
            }
        }
    }
    return false;
}

fn isUnittestContextManager(expr: ast.Node) bool {
    // Check for self.assertWarns(...), self.assertRaises(...), self.assertRaisesRegex(...), etc.
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            // Check for self.method() pattern
            if (attr.value.* == .name) {
                const obj_name = attr.value.name.id;
                if (std.mem.eql(u8, obj_name, "self")) {
                    // Check for unittest context manager methods
                    const method_name = attr.attr;
                    if (std.mem.eql(u8, method_name, "assertWarns") or
                        std.mem.eql(u8, method_name, "assertRaises") or
                        std.mem.eql(u8, method_name, "assertRaisesRegex") or
                        std.mem.eql(u8, method_name, "assertLogs") or
                        std.mem.eql(u8, method_name, "subTest"))
                    {
                        return true;
                    }
                }
            }
        }
    }
    // Tuple of context managers - check if any element is a unittest context manager
    // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
    if (expr == .tuple) {
        for (expr.tuple.elts) |elt| {
            // Handle named expression (context manager as var)
            const actual_expr = if (elt == .named_expr) elt.named_expr.value.* else elt;
            if (isUnittestContextManager(actual_expr)) {
                return true;
            }
        }
    }
    return false;
}

/// Recursively hoist variables from with statement body
/// This handles both direct assignments and nested with statements
/// Uses @TypeOf(init_expr) for comptime type inference instead of guessing
fn hoistWithBodyVars(self: *NativeCodegen, body: []const ast.Node) CodegenError!void {
    for (body) |stmt| {
        if (stmt == .assign) {
            if (stmt.assign.targets.len > 0) {
                const target = stmt.assign.targets[0];
                if (target == .name) {
                    const var_name = target.name.id;
                    // Use @TypeOf(value_expr) for proper type inference
                    try hoistVarWithExpr(self, var_name, stmt.assign.value);
                }
            }
        } else if (stmt == .with_stmt) {
            // Nested with statement - hoist its variable if it has one
            if (stmt.with_stmt.optional_vars) |var_name| {
                if (isUnittestContextManager(stmt.with_stmt.context_expr.*)) {
                    // Unittest context managers need hoisting too - err may be used after with block
                    // Hoist as ContextManager type - use const since it's only assigned once
                    try self.emitIndent();
                    try self.emit("const ");
                    try self.emit(var_name);
                    try self.emit(": runtime.unittest.ContextManager = runtime.unittest.ContextManager{};\n");
                    try self.hoisted_vars.put(var_name, {});
                } else {
                    // Use @TypeOf(context_expr) for comptime type inference
                    try hoistVarWithExpr(self, var_name, stmt.with_stmt.context_expr);
                }
            }
            // Handle tuple context managers with named expressions
            if (stmt.with_stmt.context_expr.* == .tuple) {
                for (stmt.with_stmt.context_expr.tuple.elts) |elt| {
                    if (elt == .named_expr) {
                        const named = elt.named_expr;
                        const cm_var_name = named.target.name.id;
                        const cm_expr = named.value.*;
                        if (isUnittestContextManager(cm_expr)) {
                            // Hoist unittest context manager variable - use const since only assigned once
                            try self.emitIndent();
                            try self.emit("const ");
                            try self.emit(cm_var_name);
                            try self.emit(": runtime.unittest.ContextManager = runtime.unittest.ContextManager{};\n");
                            try self.hoisted_vars.put(cm_var_name, {});
                        } else {
                            // Hoist regular context manager variable
                            try hoistVarWithExpr(self, cm_var_name, &cm_expr);
                        }
                    }
                }
            }
            // Also recursively hoist variables from nested with body
            try hoistWithBodyVars(self, stmt.with_stmt.body);
        }
    }
}

/// Hoist a variable with @TypeOf(expr) for comptime type inference
fn hoistVarWithExpr(self: *NativeCodegen, var_name: []const u8, init_expr: *const ast.Node) CodegenError!void {
    // Only hoist if not already declared in scope or previously hoisted
    if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
        try self.emitIndent();
        try self.emit("var ");
        try self.emit(var_name);
        try self.emit(": @TypeOf(");
        try self.genExpr(init_expr.*);
        try self.emit(") = undefined;\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});
    }
}

/// Hoist a variable with an explicit type (for special cases like ContextManager)
fn hoistVarWithType(self: *NativeCodegen, var_name: []const u8, type_name: []const u8) CodegenError!void {
    // Only hoist if not already declared in scope or previously hoisted
    if (!self.isDeclared(var_name) and !self.hoisted_vars.contains(var_name)) {
        try self.emitIndent();
        try self.emit("var ");
        try self.emit(var_name);
        try self.emit(": ");
        try self.emit(type_name);
        try self.emit(" = undefined;\n");

        // Mark as hoisted so assignment generation skips declaration
        try self.hoisted_vars.put(var_name, {});
    }
}

/// Generate with statement (context manager)
/// with open("file") as f: body => var f = ...; defer f.close(); body
/// In Python, 'f' is accessible after the with block, so we don't use nested blocks
pub fn genWith(self: *NativeCodegen, with_node: ast.Node.With) CodegenError!void {
    // Skip unittest context managers (assertWarns, assertRaises, etc.)
    // These are test helpers that don't have runtime implementations yet
    if (isUnittestContextManager(with_node.context_expr.*)) {
        // Consume the arguments to avoid "unused local constant" errors
        // e.g., with self.assertRaisesRegex(TypeError, msg): -> _ = msg;
        // But only if the variable is truly unused (checked via semantic analysis)
        if (with_node.context_expr.* == .call) {
            const call = with_node.context_expr.call;
            for (call.args) |arg| {
                // Only emit discard for name references (variables) that are unused
                if (arg == .name) {
                    const var_name = arg.name.id;
                    if (self.isVarUnused(var_name)) {
                        try self.emitIndent();
                        try self.emit("_ = ");
                        try self.genExpr(arg);
                        try self.emit(";\n");
                    }
                }
            }
        }

        // If there's a variable name (as cm), declare it as a dummy value
        // Python code might use cm.exception.args[0] after the with block
        if (with_node.optional_vars) |var_name| {
            // Check if variable was hoisted or already declared (for multiple assertRaises in same scope)
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const is_declared = self.isDeclared(var_name);
            const needs_decl = !is_hoisted and !is_declared;

            // Only emit declaration if variable not already declared
            // For repeated with statements using same variable, the const is already set
            if (needs_decl) {
                try self.emitIndent();
                // Use const for context manager variables (they're read-only)
                try self.emit("const ");
                try self.emit(var_name);
                try self.emit(" = runtime.unittest.ContextManager{};\n");
                // Always discard pointer to suppress unused warning
                // Using pointer avoids "pointless discard" when variable IS used later
                try self.emitIndent();
                try self.emit("_ = &");
                try self.emit(var_name);
                try self.emit(";\n");
                try self.declareVar(var_name);
            }
        }

        // Handle tuple of context managers with named expressions
        // e.g., with (self.assertRaises(ValueError) as err, support.Stopwatch() as sw):
        if (with_node.context_expr.* == .tuple) {
            for (with_node.context_expr.tuple.elts) |elt| {
                if (elt == .named_expr) {
                    const named = elt.named_expr;
                    const var_name = named.target.name.id;
                    const cm_expr = named.value.*;

                    // Check if variable was hoisted or already declared
                    const is_hoisted = self.hoisted_vars.contains(var_name);
                    const is_declared = self.isDeclared(var_name);
                    const needs_decl = !is_hoisted and !is_declared;

                    // Check if this is a unittest context manager (assertRaises, etc.)
                    if (isUnittestContextManager(cm_expr)) {
                        // Emit dummy ContextManager for assertRaises/assertRaisesRegex
                        try self.emitIndent();
                        if (needs_decl) {
                            try self.emit("const ");
                        }
                        try self.emit(var_name);
                        try self.emit(" = runtime.unittest.ContextManager{};\n");
                        try self.emitIndent();
                        try self.emit("_ = &");
                        try self.emit(var_name);
                        try self.emit(";\n");
                    } else {
                        // Emit actual context manager (e.g., support.Stopwatch())
                        try self.emitIndent();
                        if (needs_decl) {
                            try self.emit("var ");
                        }
                        try self.emit(var_name);
                        try self.emit(" = ");
                        try self.genExpr(cm_expr);
                        try self.emit(";\n");
                        try self.emitIndent();
                        try self.emit("defer ");
                        try self.emit(var_name);
                        try self.emit(".close();\n");
                    }
                    if (needs_decl) {
                        try self.declareVar(var_name);
                    }
                }
            }
        }

        // For assertRaises/assertRaisesRegex, set context flag so builtins use catch instead of try
        // For assertWarns/assertLogs, just generate body normally
        const is_raises_context = isAssertRaisesContext(with_node.context_expr.*);

        if (is_raises_context) {
            const was_in_assert_raises = self.in_assert_raises_context;
            self.in_assert_raises_context = true;

            for (with_node.body) |stmt| {
                // For expression statements that might error, wrap the expression in catch
                // Use comptime check to handle both error unions and non-error types
                if (stmt == .expr_stmt) {
                    try self.emitIndent();
                    try self.emit("{ const __ar_expr = ");
                    try self.genExpr(stmt.expr_stmt.value.*);
                    try self.emit("; if (@typeInfo(@TypeOf(__ar_expr)) == .error_union) { _ = __ar_expr catch {}; } }\n");
                } else {
                    try self.generateStmt(stmt);
                }
            }

            // Restore context flag
            self.in_assert_raises_context = was_in_assert_raises;
        } else {
            // For assertWarns, assertLogs, subTest - just generate body normally
            for (with_node.body) |stmt| {
                try self.generateStmt(stmt);
            }
        }
        return;
    }

    // If there's a variable name (as f), declare it at current scope
    if (with_node.optional_vars) |var_name| {
        // Check if already declared or hoisted (for nested with)
        const is_declared = self.isDeclared(var_name);
        const is_hoisted = self.hoisted_vars.contains(var_name);
        const needs_var = !is_declared and !is_hoisted;

        // Infer and register the type of the context expression
        // This is critical for operations like `for line in file:` to work correctly
        const context_type = try self.type_inferrer.inferExpr(with_node.context_expr.*);
        try self.type_inferrer.var_types.put(var_name, context_type);

        // Declare variable at outer scope so it's accessible after with block
        try self.emitIndent();
        if (needs_var) {
            // Use const for context manager variables (they're not reassigned)
            try self.emit("const ");
        }
        try self.emit(var_name);
        try self.emit(" = ");
        try self.genExpr(with_node.context_expr.*);
        try self.emit(";\n");

        // Mark as declared for body (unless hoisted)
        if (needs_var) {
            try self.declareVar(var_name);
        }

        // Open a block for defer scope - defer fires at end of this block, not function
        // This ensures file is closed immediately after with body completes
        try self.emitIndent();
        try self.emit("{\n");
        self.indent();

        // Add defer for cleanup (close, __exit__, etc.)
        // For file objects, emit runtime.PyFile.close(f) as static method
        // For other context managers, emit f.close()
        try self.emitIndent();
        if (context_type == .file) {
            try self.emit("defer runtime.PyFile.close(");
            try self.emit(var_name);
            try self.emit(");\n");
        } else {
            try self.emit("defer ");
            try self.emit(var_name);
            try self.emit(".close();\n");
        }
    } else {
        // No variable - just execute context expression and defer cleanup
        // First, hoist any variables declared in body (similar to try-except)
        // This is needed because Python allows variables defined inside with blocks
        // to be used after the block ends
        try hoistWithBodyVars(self, with_node.body);

        try self.emitIndent();
        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const __ctx = ");
        try self.genExpr(with_node.context_expr.*);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("defer __ctx.close();\n");
    }

    // Generate body
    // If we're inside an assertRaises context (from a parent with statement),
    // wrap expression statements in error-catching code
    for (with_node.body) |stmt| {
        if (self.in_assert_raises_context and stmt == .expr_stmt) {
            // Wrap expression in error catch for assertRaises context
            try self.emitIndent();
            try self.emit("{ const __ar_expr = ");
            try self.genExpr(stmt.expr_stmt.value.*);
            try self.emit("; if (@typeInfo(@TypeOf(__ar_expr)) == .error_union) { _ = __ar_expr catch {}; } }\n");
        } else {
            try self.generateStmt(stmt);
        }
    }

    // Close block for both cases - with variable and without
    // When there's a variable, we opened a block for defer scope
    // When there's no variable, we also opened a block
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate raise statement
/// raise ValueError("msg") => return error.ValueError
/// raise => return error.Exception
/// NOTE: We use Zig errors so try/except can catch them. The error message is lost,
/// but exception handling works correctly.
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    try self.emitIndent();

    if (raise_node.exc) |exc| {
        // Check if this is an exception constructor call: raise ValueError("msg")
        if (exc.* == .call) {
            const call = exc.call;
            if (call.func.* == .name) {
                const exc_name = call.func.name.id;
                // Check if it's a known exception type
                if (ExceptionTypes.has(exc_name)) {
                    // Generate: return error.ValueError
                    try self.emit("return error.");
                    try self.emit(exc_name);
                    try self.emit(";\n");
                    return;
                }
            }
        }
        // Check if this is just an exception name: raise TypeError
        if (exc.* == .name) {
            const exc_name = exc.name.id;
            if (ExceptionTypes.has(exc_name)) {
                // Generate: return error.TypeError
                try self.emit("return error.");
                try self.emit(exc_name);
                try self.emit(";\n");
                return;
            }
        }
        // Fallback for other raise expressions - use generic error
        try self.emit("return error.Exception;\n");
    } else {
        // bare raise - use generic error
        try self.emit("return error.Exception;\n");
    }
}

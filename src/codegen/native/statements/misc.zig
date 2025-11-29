/// Miscellaneous statement code generation (return, import, assert, global, del, raise)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

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

/// Generate return statement with tail-call optimization
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    try self.emitIndent();

    if (ret.value) |value| {
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

        // Normal return
        try self.emit("return ");
        try self.genExpr(value.*);
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
        if (info.zig_import) |zig_import| {
            try self.emitIndent();
            try self.emit("const ");
            try self.emit(alias);
            try self.emit(" = ");
            try self.emit(zig_import);
            try self.emit(";\n");
        }
    }
}

/// Generate from-import statement: from module import names
/// Import statements are now handled at module level in main.zig
/// This function is a no-op since imports are collected and generated in PHASE 3
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    _ = self;
    _ = import;
    // No-op: imports are handled at module level, not during statement generation
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
        // assert x, "message"
        try self.emit("std.debug.panic(\"AssertionError: {s}\", .{");
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

/// Known Python exception types
const ExceptionTypes = std.StaticStringMap(void).initComptime(.{
    .{ "ValueError", {} },
    .{ "TypeError", {} },
    .{ "RuntimeError", {} },
    .{ "KeyError", {} },
    .{ "IndexError", {} },
    .{ "ZeroDivisionError", {} },
    .{ "AttributeError", {} },
    .{ "NameError", {} },
    .{ "FileNotFoundError", {} },
    .{ "IOError", {} },
    .{ "Exception", {} },
    .{ "StopIteration", {} },
    .{ "NotImplementedError", {} },
    .{ "AssertionError", {} },
    .{ "OverflowError", {} },
    .{ "ImportError", {} },
    .{ "ModuleNotFoundError", {} },
    .{ "OSError", {} },
    .{ "PermissionError", {} },
    .{ "TimeoutError", {} },
    .{ "ConnectionError", {} },
    .{ "RecursionError", {} },
    .{ "MemoryError", {} },
    .{ "LookupError", {} },
    .{ "ArithmeticError", {} },
    .{ "BufferError", {} },
    .{ "EOFError", {} },
    .{ "GeneratorExit", {} },
    .{ "SystemExit", {} },
    .{ "KeyboardInterrupt", {} },
});

/// Check if with expression is a unittest context manager that should be skipped
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
    return false;
}

/// Generate with statement (context manager)
/// with open("file") as f: body => var f = ...; defer f.close(); body
/// In Python, 'f' is accessible after the with block, so we don't use nested blocks
pub fn genWith(self: *NativeCodegen, with_node: ast.Node.With) CodegenError!void {
    // Skip unittest context managers (assertWarns, assertRaises, etc.)
    // These are test helpers that don't have runtime implementations yet
    if (isUnittestContextManager(with_node.context_expr.*)) {
        // Just generate body without the context manager wrapper
        for (with_node.body) |stmt| {
            try self.generateStmt(stmt);
        }
        return;
    }

    // If there's a variable name (as f), declare it at current scope
    if (with_node.optional_vars) |var_name| {
        // Check if already declared (for nested with or reassignment)
        const is_first = !self.isDeclared(var_name);

        try self.emitIndent();
        if (is_first) {
            try self.emit("var ");
        }
        try self.emit(var_name);
        try self.emit(" = ");
        try self.genExpr(with_node.context_expr.*);
        try self.emit(";\n");

        // Add defer for cleanup (close, __exit__, etc.)
        // For file objects, emit f.close(); for context managers, emit __exit__
        try self.emitIndent();
        try self.emit("defer ");
        try self.emit(var_name);
        try self.emit(".close();\n");

        // Mark as declared for body
        if (is_first) {
            try self.declareVar(var_name);
        }
    } else {
        // No variable - just execute context expression and defer cleanup
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
    for (with_node.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Close block if no variable
    if (with_node.optional_vars == null) {
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }
}

/// Generate raise statement
/// raise ValueError("msg") => std.debug.panic("ValueError: {s}", .{"msg"})
/// raise => std.debug.panic("Unhandled exception", .{})
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
                    // Generate: std.debug.panic("ValueError: {s}", .{"msg"})
                    try self.emit("std.debug.panic(\"");
                    try self.emit(exc_name);
                    if (call.args.len > 0) {
                        try self.emit(": {s}\", .{");
                        try self.genExpr(call.args[0]);
                        try self.emit("});\n");
                    } else {
                        try self.emit("\", .{});\n");
                    }
                    return;
                }
            }
        }
        // Check if this is just an exception name: raise TypeError
        if (exc.* == .name) {
            const exc_name = exc.name.id;
            if (ExceptionTypes.has(exc_name)) {
                // Generate: std.debug.panic("TypeError", .{})
                try self.emit("std.debug.panic(\"");
                try self.emit(exc_name);
                try self.emit("\", .{});\n");
                return;
            }
        }
        // Fallback for other raise expressions
        try self.emit("std.debug.panic(\"Exception: {any}\", .{");
        try self.genExpr(exc.*);
        try self.emit("});\n");
    } else {
        // bare raise
        try self.emit("std.debug.panic(\"Unhandled exception\", .{});\n");
    }
}

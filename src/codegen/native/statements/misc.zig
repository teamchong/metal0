/// Miscellaneous statement code generation (return, import, assert, global, del, raise)
const std = @import("std");
const ast = @import("../../../ast.zig");
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
/// Import statements are now handled at module level in main.zig
/// This function is a no-op since imports are collected and generated in PHASE 3
pub fn genImport(self: *NativeCodegen, import: ast.Node.Import) CodegenError!void {
    _ = self;
    _ = import;
    // No-op: imports are handled at module level, not during statement generation
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

/// Generate raise statement
/// raise ValueError("msg") => std.debug.panic("ValueError: {s}", .{"msg"})
/// raise => std.debug.panic("Unhandled exception", .{})
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    try self.emitIndent();

    if (raise_node.exc) |exc| {
        // raise Exception("msg")
        // For now, just panic with the exception type
        try self.emit("std.debug.panic(\"Exception: {any}\", .{");
        try self.genExpr(exc.*);
        try self.emit("});\n");
    } else {
        // bare raise
        try self.emit("std.debug.panic(\"Unhandled exception\", .{});\n");
    }
}

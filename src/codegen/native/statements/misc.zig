/// Miscellaneous statement code generation (return, import, assert, global, del, raise)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// Re-export print statement generation
pub const genPrint = @import("print.zig").genPrint;

/// Generate return statement
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    try self.emitIndent();
    try self.emit("return ");
    if (ret.value) |value| {
        try self.genExpr(value.*);
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
    try self.output.appendSlice(self.allocator, "// del statement (no-op in AOT)\n");
}

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!(condition)) { std.debug.panic("Assertion failed", .{}); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (!(");
    try self.genExpr(assert_node.condition.*);
    try self.output.appendSlice(self.allocator, ")) {\n");

    self.indent();
    try self.emitIndent();

    if (assert_node.msg) |msg| {
        // assert x, "message"
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"AssertionError: {s}\", .{");
        try self.genExpr(msg.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // assert x
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"AssertionError\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate raise statement
/// raise ValueError("msg") => std.debug.panic("ValueError: {s}", .{"msg"})
/// raise => std.debug.panic("Unhandled exception", .{})
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    try self.emitIndent();

    if (raise_node.exc) |exc| {
        // raise Exception("msg")
        // For now, just panic with the exception type
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Exception: {any}\", .{");
        try self.genExpr(exc.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // bare raise
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Unhandled exception\", .{});\n");
    }
}

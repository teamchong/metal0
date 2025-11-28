/// Python code module - Interactive interpreter base classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code.InteractiveConsole class
pub fn genInteractiveConsole(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .locals = @as(?*anyopaque, null), .filename = \"<console>\" }");
}

/// Generate code.InteractiveInterpreter class
pub fn genInteractiveInterpreter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .locals = @as(?*anyopaque, null) }");
}

/// Generate code.compile_command(source, filename, symbol)
pub fn genCompile_command(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate code.interact(banner=None, readfunc=None, local=None, exitmsg=None)
pub fn genInteract(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

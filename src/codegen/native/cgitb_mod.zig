/// Python cgitb module - Traceback manager for CGI scripts (deprecated 3.11)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate cgitb.enable(display=1, logdir=None, context=5, format='html')
pub fn genEnable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgitb.handler(info=None)
pub fn genHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgitb.text(info, context=5)
pub fn genText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate cgitb.html(info, context=5)
pub fn genHtml(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"<html></html>\"");
}

/// Generate cgitb.reset()
pub fn genReset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgitb.Hook(display=1, logdir=None, context=5, file=None, format='html')
pub fn genHook(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .display = 1, .logdir = null, .context = 5, .file = null, .format = \"html\" }");
}

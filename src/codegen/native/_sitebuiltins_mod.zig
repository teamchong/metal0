/// Python _sitebuiltins module - Internal site builtins support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sitebuiltins.Quitter(name, eof)
pub fn genQuitter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"quit\", .eof = \"Ctrl-D (i.e. EOF)\" }");
}

/// Generate _sitebuiltins._Printer(name, data, files=(), dirs=())
pub fn genPrinter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .data = \"\" }");
}

/// Generate _sitebuiltins._Helper()
pub fn genHelper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

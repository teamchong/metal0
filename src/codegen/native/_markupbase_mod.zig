/// Python _markupbase module - Internal markup base support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _markupbase.ParserBase class
pub fn genParserBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .lasttag = \"\", .interesting = null }");
}

/// Generate ParserBase.reset()
pub fn genReset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ParserBase.getpos()
pub fn genGetpos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, 1), @as(i64, 0) }");
}

/// Generate ParserBase.updatepos(i, j)
pub fn genUpdatepos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate ParserBase.error(message)
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ParserError");
}

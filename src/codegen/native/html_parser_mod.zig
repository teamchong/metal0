/// Python html.parser module - HTML parsing
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "HTMLParser", genHTMLParser },
    .{ "HTMLParseError", genHTMLParseError },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate html.parser.HTMLParser(*, convert_charrefs=True)
pub fn genHTMLParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .convert_charrefs = true }");
}

// ============================================================================
// Exception
// ============================================================================

pub fn genHTMLParseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.HTMLParseError");
}

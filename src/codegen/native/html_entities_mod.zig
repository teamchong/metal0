/// Python html.entities module - HTML entity definitions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate html.entities.html5 dict (HTML5 named character references)
pub fn genHtml5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate html.entities.name2codepoint dict (map name to Unicode codepoint)
pub fn genName2codepoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate html.entities.codepoint2name dict (map codepoint to name)
pub fn genCodepoint2name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate html.entities.entitydefs dict (ISO Latin-1 character entity definitions)
pub fn genEntitydefs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

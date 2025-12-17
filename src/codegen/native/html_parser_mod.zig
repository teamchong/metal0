/// Python html.parser module - HTML parsing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "HTMLParser", genHTMLParser },
    .{ "HTMLParseError", genHTMLParseError },
});

fn genHTMLParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .convert_charrefs = true }"), builder_mod.EmitConfig.forExpression());
}

fn genHTMLParseError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.HTMLParseError"), builder_mod.EmitConfig.forExpression());
}

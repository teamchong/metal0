/// Python _elementtree module - Internal ElementTree support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Element", genElement },
    .{ "SubElement", genSubElement },
    .{ "TreeBuilder", genTreeBuilder },
    .{ "XMLParser", genXMLParser },
    .{ "ParseError", genParseError },
});

fn genElement(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_el: {{ const tag = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_el .{{ .tag = tag, .attrib = .{{}}, .text = null, .tail = null }}; }})", .{id});
}

fn genSubElement(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_sub: {{ const tag = ", .{id});
    try self.genExpr(args[1]);
    try self.emitFmt("; break :__m{d}_sub .{{ .tag = tag, .attrib = .{{}}, .text = null, .tail = null }}; }})", .{id});
}

fn genTreeBuilder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .element_factory = null, .data = &[_][]const u8{}, .elem = &[_]@TypeOf(.{}){}, .last = null }"), builder_mod.EmitConfig.forExpression());
}

fn genXMLParser(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .target = null, .parser = null }"), builder_mod.EmitConfig.forExpression());
}

fn genParseError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ParseError"), builder_mod.EmitConfig.forExpression());
}

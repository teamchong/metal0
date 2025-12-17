/// Python _elementtree module - Internal ElementTree support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

const elem_default = ".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Element", genElement },
    .{ "SubElement", genSubElement },
    .{ "TreeBuilder", h.c(".{ .element_factory = null, .data = &[_][]const u8{}, .elem = &[_]@TypeOf(.{}){}, .last = null }") },
    .{ "XMLParser", h.c(".{ .target = null, .parser = null }") }, .{ "ParseError", h.err("ParseError") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(elem_default); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_el: {{ const tag = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_el .{{ .tag = tag, .attrib = .{{}}, .text = null, .tail = null }}; }})", .{id});
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit(elem_default); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_sub: {{ const tag = ", .{id}); try self.genExpr(args[1]);
    try self.emitFmt("; break :__m{d}_sub .{{ .tag = tag, .attrib = .{{}}, .text = null, .tail = null }}; }})", .{id});
}

/// Python _elementtree module - Internal ElementTree support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Element", genElement }, .{ "SubElement", genSubElement },
    .{ "TreeBuilder", genTreeBuilder }, .{ "XMLParser", genXMLParser }, .{ "ParseError", genParseError },
});

const elem_default = ".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }";

fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const tag = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }"); }
    else { try self.emit(elem_default); }
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const tag = "); try self.genExpr(args[1]); try self.emit("; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }"); }
    else { try self.emit(elem_default); }
}

fn genTreeBuilder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, ".{ .element_factory = null, .data = &[_][]const u8{}, .elem = &[_]@TypeOf(.{}){}, .last = null }");
}

fn genXMLParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, ".{ .target = null, .parser = null }");
}

fn genParseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ParseError"); }

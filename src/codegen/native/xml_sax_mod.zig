/// Python xml.sax module - SAX XML parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "make_parser", genEmpty }, .{ "parse", genUnit }, .{ "parseString", genUnit },
    .{ "ContentHandler", genEmpty }, .{ "DTDHandler", genEmpty }, .{ "EntityResolver", genEmpty }, .{ "ErrorHandler", genEmpty },
    .{ "InputSource", genInputSource }, .{ "AttributesImpl", genAttrsImpl }, .{ "AttributesNSImpl", genAttrsNSImpl },
    .{ "SAXException", genSAXErr }, .{ "SAXNotRecognizedException", genSAXNotRecogErr },
    .{ "SAXNotSupportedException", genSAXNotSuppErr }, .{ "SAXParseException", genSAXParseErr },
});

fn genInputSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const system_id = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }; }"); }
    else { try self.emit(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }"); }
}
fn genAttrsImpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .attrs = .{} }"); }
fn genAttrsNSImpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .attrs = .{}, .qnames = .{} }"); }
fn genSAXErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SAXException"); }
fn genSAXNotRecogErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SAXNotRecognizedException"); }
fn genSAXNotSuppErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SAXNotSupportedException"); }
fn genSAXParseErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SAXParseException"); }

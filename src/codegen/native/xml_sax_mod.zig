/// Python xml.sax module - SAX XML parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "make_parser", genConst(".{}") }, .{ "parse", genConst("{}") }, .{ "parseString", genConst("{}") },
    .{ "ContentHandler", genConst(".{}") }, .{ "DTDHandler", genConst(".{}") }, .{ "EntityResolver", genConst(".{}") }, .{ "ErrorHandler", genConst(".{}") },
    .{ "InputSource", genInputSource }, .{ "AttributesImpl", genConst(".{ .attrs = .{} }") }, .{ "AttributesNSImpl", genConst(".{ .attrs = .{}, .qnames = .{} }") },
    .{ "SAXException", genConst("error.SAXException") }, .{ "SAXNotRecognizedException", genConst("error.SAXNotRecognizedException") },
    .{ "SAXNotSupportedException", genConst("error.SAXNotSupportedException") }, .{ "SAXParseException", genConst("error.SAXParseException") },
});

fn genInputSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const system_id = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }; }"); }
    else try self.emit(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }");
}

/// Python xml.sax module - SAX XML parsing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "make_parser", h.c(".{}") }, .{ "parse", h.c("{}") }, .{ "parseString", h.c("{}") },
    .{ "ContentHandler", h.c(".{}") }, .{ "DTDHandler", h.c(".{}") }, .{ "EntityResolver", h.c(".{}") }, .{ "ErrorHandler", h.c(".{}") },
    .{ "InputSource", genInputSource },
    .{ "AttributesImpl", h.c(".{ .attrs = .{} }") }, .{ "AttributesNSImpl", h.c(".{ .attrs = .{}, .qnames = .{} }") },
    .{ "SAXException", h.err("SAXException") }, .{ "SAXNotRecognizedException", h.err("SAXNotRecognizedException") },
    .{ "SAXNotSupportedException", h.err("SAXNotSupportedException") }, .{ "SAXParseException", h.err("SAXParseException") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genInputSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }"); return; }
    try self.withInlineBlock("is", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const system_id = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; break :{s} .{{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }}", .{label});
        }
    }.emit);
}

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

const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

fn genInputSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitRaw(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }");
        try self.flushBuilder();
        return;
    }
    const sys_id_val = try self.captureExpr(args[0]);
    try b.withLabeledBlock("__is", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, ctx: ZigValue) !void {
            try bld.emitConstWithValue("system_id", "", ctx, "");
            try scope.breakWithRaw(".{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }");
        }
    }.emit, sys_id_val);
    try self.flushBuilder();
}

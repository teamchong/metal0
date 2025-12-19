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
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("is", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const system_id = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; break :{s} .{{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }}", .{label});
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

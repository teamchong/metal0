/// Python mimetypes module - MIME type mapping
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "guess_type", genGuessType },
    .{ "guess_all_extensions", genGuessAllExtensions },
    .{ "guess_extension", genGuessExtension },
    .{ "init", genInit },
    .{ "read_mime_types", genReadMimeTypes },
    .{ "add_type", genAddType },
    .{ "MimeTypes", genMimeTypes },
    .{ "knownfiles", genKnownfiles },
    .{ "inited", genInited },
    .{ "suffix_map", genSuffixMap },
    .{ "encodings_map", genEncodingsMap },
    .{ "types_map", genTypesMap },
    .{ "common_types", genCommonTypes },
});

fn genGuessType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(?[]const u8, null), @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genGuessAllExtensions(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genGuessExtension(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[]const u8, null)"), builder_mod.EmitConfig.forExpression());
}

fn genInit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genReadMimeTypes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?@TypeOf(.{}), null)"), builder_mod.EmitConfig.forExpression());
}

fn genAddType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genMimeTypes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .encodings_map = .{}, .suffix_map = .{}, .types_map = .{ .{}, .{} }, .types_map_inv = .{ .{}, .{} } }"), builder_mod.EmitConfig.forExpression());
}

fn genKnownfiles(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"/etc/mime.types\", \"/etc/httpd/mime.types\", \"/etc/httpd/conf/mime.types\", \"/etc/apache/mime.types\", \"/etc/apache2/mime.types\", \"/usr/local/etc/httpd/conf/mime.types\", \"/usr/local/lib/netscape/mime.types\", \"/usr/local/etc/mime.types\" }"), builder_mod.EmitConfig.forExpression());
}

fn genInited(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genSuffixMap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genEncodingsMap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genTypesMap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCommonTypes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

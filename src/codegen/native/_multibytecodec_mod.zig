/// Python _multibytecodec module - Multi-byte codec support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "multibyte_codec", genMultibyteCodec },
    .{ "multibyte_incremental_encoder", genIncrementalEncoder },
    .{ "multibyte_incremental_decoder", genIncrementalDecoder },
    .{ "multibyte_stream_reader", genStreamReader },
    .{ "multibyte_stream_writer", genStreamWriter },
    .{ "create_codec", genCreateCodec },
});

fn genMultibyteCodec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementalEncoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .codec = null, .errors = \"strict\" }"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementalDecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .codec = null, .errors = \"strict\" }"), builder_mod.EmitConfig.forExpression());
}

fn genStreamReader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .stream = null, .errors = \"strict\" }"), builder_mod.EmitConfig.forExpression());
}

fn genStreamWriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .stream = null, .errors = \"strict\" }"), builder_mod.EmitConfig.forExpression());
}

fn genCreateCodec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\" }"), builder_mod.EmitConfig.forExpression());
}

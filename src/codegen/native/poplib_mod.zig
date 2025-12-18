/// Python poplib module - POP3 protocol client
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "POP3", genPOP3 },
    .{ "POP3_SSL", genPOP3SSL },
    .{ "POP3_PORT", genPOP3Port },
    .{ "POP3_SSL_PORT", genPOP3SSLPort },
    .{ "error_proto", genErrorProto },
});

fn genPOP3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 110), .timeout = @as(f64, -1.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genPOP3SSL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 995), .timeout = @as(f64, -1.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genPOP3Port(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(110), builder_mod.EmitConfig.forExpression());
}

fn genPOP3SSLPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(995), builder_mod.EmitConfig.forExpression());
}

fn genErrorProto(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.POP3ProtoError"), builder_mod.EmitConfig.forExpression());
}

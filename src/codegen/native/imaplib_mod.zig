/// Python imaplib module - IMAP4 protocol client
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "IMAP4", genIMAP4 },
    .{ "IMAP4_SSL", genIMAP4SSL },
    .{ "IMAP4_stream", genIMAP4Stream },
    .{ "IMAP4_PORT", genIMAP4Port },
    .{ "IMAP4_SSL_PORT", genIMAP4SSLPort },
    .{ "Commands", genCommands },
    .{ "IMAP4.error", genIMAP4Error },
    .{ "IMAP4.abort", genIMAP4Abort },
    .{ "IMAP4.readonly", genIMAP4Readonly },
    .{ "Internaldate2tuple", genInternaldate2tuple },
    .{ "Int2AP", genInt2AP },
    .{ "ParseFlags", genParseFlags },
    .{ "Time2Internaldate", genTime2Internaldate },
});

fn genIMAP4(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 143), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4SSL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 993), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4Stream(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .state = \"LOGOUT\" }"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4Port(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(143), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4SSLPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(993), builder_mod.EmitConfig.forExpression());
}

fn genCommands(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4Error(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.IMAP4Error"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4Abort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.IMAP4Abort"), builder_mod.EmitConfig.forExpression());
}

fn genIMAP4Readonly(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.IMAP4Readonly"), builder_mod.EmitConfig.forExpression());
}

fn genInternaldate2tuple(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genInt2AP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genParseFlags(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genTime2Internaldate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

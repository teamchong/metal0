/// Python ftplib module - FTP protocol client
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FTP", genFTP },
    .{ "FTP_TLS", genFTPTLS },
    .{ "FTP_PORT", genFTPPort },
    .{ "error", genError },
    .{ "error_reply", genErrorReply },
    .{ "error_temp", genErrorTemp },
    .{ "error_perm", genErrorPerm },
    .{ "error_proto", genErrorProto },
    .{ "all_errors", genAllErrors },
});

fn genFTP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFTPTLS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFTPPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(21), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.FTPError"), builder_mod.EmitConfig.forExpression());
}

fn genErrorReply(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.FTPReplyError"), builder_mod.EmitConfig.forExpression());
}

fn genErrorTemp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.FTPTempError"), builder_mod.EmitConfig.forExpression());
}

fn genErrorPerm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.FTPPermError"), builder_mod.EmitConfig.forExpression());
}

fn genErrorProto(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.FTPProtoError"), builder_mod.EmitConfig.forExpression());
}

fn genAllErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]type{ error.FTPError, error.FTPReplyError, error.FTPTempError, error.FTPPermError, error.FTPProtoError }"), builder_mod.EmitConfig.forExpression());
}

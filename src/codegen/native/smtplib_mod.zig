/// Python smtplib module - SMTP protocol client
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SMTP", genSMTP },
    .{ "SMTP_SSL", genSMTPSSL },
    .{ "LMTP", genLMTP },
    .{ "SMTP_PORT", genSMTPPort },
    .{ "SMTP_SSL_PORT", genSMTPSSLPort },
    .{ "SMTPException", genSMTPException },
    .{ "SMTPServerDisconnected", genSMTPServerDisconnected },
    .{ "SMTPResponseException", genSMTPResponseException },
    .{ "SMTPSenderRefused", genSMTPSenderRefused },
    .{ "SMTPRecipientsRefused", genSMTPRecipientsRefused },
    .{ "SMTPDataError", genSMTPDataError },
    .{ "SMTPConnectError", genSMTPConnectError },
    .{ "SMTPHeloError", genSMTPHeloError },
    .{ "SMTPAuthenticationError", genSMTPAuthenticationError },
    .{ "SMTPNotSupportedError", genSMTPNotSupportedError },
});

fn genSMTP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 25), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPSSL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 465), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genLMTP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .host = \"\", .port = @as(i32, 2003), .local_hostname = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(25), builder_mod.EmitConfig.forExpression());
}

fn genSMTPSSLPort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(465), builder_mod.EmitConfig.forExpression());
}

fn genSMTPException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPException"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPServerDisconnected(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPServerDisconnected"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPResponseException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPResponseException"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPSenderRefused(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPSenderRefused"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPRecipientsRefused(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPRecipientsRefused"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPDataError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPDataError"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPConnectError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPConnectError"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPHeloError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPHeloError"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPAuthenticationError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPAuthenticationError"), builder_mod.EmitConfig.forExpression());
}

fn genSMTPNotSupportedError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SMTPNotSupportedError"), builder_mod.EmitConfig.forExpression());
}

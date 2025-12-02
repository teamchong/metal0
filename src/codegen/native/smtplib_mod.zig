/// Python smtplib module - SMTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genSMTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 25), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }"); }
fn genSMTP_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 465), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }"); }
fn genLMTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 2003), .local_hostname = @as(?[]const u8, null) }"); }
fn genPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 25)"); }
fn genSslPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 465)"); }
fn genEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPException"); }
fn genDisc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPServerDisconnected"); }
fn genResp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPResponseException"); }
fn genSend(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPSenderRefused"); }
fn genRecip(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPRecipientsRefused"); }
fn genData(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPDataError"); }
fn genConn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPConnectError"); }
fn genHelo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPHeloError"); }
fn genAuth(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPAuthenticationError"); }
fn genNotSupp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SMTPNotSupportedError"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SMTP", genSMTP }, .{ "SMTP_SSL", genSMTP_SSL }, .{ "LMTP", genLMTP },
    .{ "SMTP_PORT", genPort }, .{ "SMTP_SSL_PORT", genSslPort },
    .{ "SMTPException", genEx }, .{ "SMTPServerDisconnected", genDisc }, .{ "SMTPResponseException", genResp },
    .{ "SMTPSenderRefused", genSend }, .{ "SMTPRecipientsRefused", genRecip }, .{ "SMTPDataError", genData },
    .{ "SMTPConnectError", genConn }, .{ "SMTPHeloError", genHelo }, .{ "SMTPAuthenticationError", genAuth }, .{ "SMTPNotSupportedError", genNotSupp },
});

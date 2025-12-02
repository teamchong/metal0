/// Python smtplib module - SMTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SMTP", genConst(".{ .host = \"\", .port = @as(i32, 25), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }") },
    .{ "SMTP_SSL", genConst(".{ .host = \"\", .port = @as(i32, 465), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }") },
    .{ "LMTP", genConst(".{ .host = \"\", .port = @as(i32, 2003), .local_hostname = @as(?[]const u8, null) }") },
    .{ "SMTP_PORT", genConst("@as(i32, 25)") }, .{ "SMTP_SSL_PORT", genConst("@as(i32, 465)") },
    .{ "SMTPException", genConst("error.SMTPException") }, .{ "SMTPServerDisconnected", genConst("error.SMTPServerDisconnected") },
    .{ "SMTPResponseException", genConst("error.SMTPResponseException") }, .{ "SMTPSenderRefused", genConst("error.SMTPSenderRefused") },
    .{ "SMTPRecipientsRefused", genConst("error.SMTPRecipientsRefused") }, .{ "SMTPDataError", genConst("error.SMTPDataError") },
    .{ "SMTPConnectError", genConst("error.SMTPConnectError") }, .{ "SMTPHeloError", genConst("error.SMTPHeloError") },
    .{ "SMTPAuthenticationError", genConst("error.SMTPAuthenticationError") }, .{ "SMTPNotSupportedError", genConst("error.SMTPNotSupportedError") },
});

/// Python smtplib module - SMTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate smtplib.SMTP class
pub fn genSMTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 25), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }");
}

/// Generate smtplib.SMTP_SSL class
pub fn genSMTP_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 465), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }");
}

/// Generate smtplib.LMTP class
pub fn genLMTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 2003), .local_hostname = @as(?[]const u8, null) }");
}

// ============================================================================
// SMTP response codes
// ============================================================================

pub fn genSMTP_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 25)");
}

pub fn genSMTP_SSL_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 465)");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genSMTPException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPException");
}

pub fn genSMTPServerDisconnected(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPServerDisconnected");
}

pub fn genSMTPResponseException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPResponseException");
}

pub fn genSMTPSenderRefused(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPSenderRefused");
}

pub fn genSMTPRecipientsRefused(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPRecipientsRefused");
}

pub fn genSMTPDataError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPDataError");
}

pub fn genSMTPConnectError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPConnectError");
}

pub fn genSMTPHeloError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPHeloError");
}

pub fn genSMTPAuthenticationError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPAuthenticationError");
}

pub fn genSMTPNotSupportedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SMTPNotSupportedError");
}

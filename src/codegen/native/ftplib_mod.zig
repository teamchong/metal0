/// Python ftplib module - FTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate ftplib.FTP class
pub fn genFTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }");
}

/// Generate ftplib.FTP_TLS class
pub fn genFTP_TLS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }");
}

// ============================================================================
// Port constants
// ============================================================================

pub fn genFTP_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 21)");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FTPError");
}

pub fn genError_reply(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FTPReplyError");
}

pub fn genError_temp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FTPTempError");
}

pub fn genError_perm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FTPPermError");
}

pub fn genError_proto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FTPProtoError");
}

// ============================================================================
// Response codes
// ============================================================================

pub fn genAll_errors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]type{ error.FTPError, error.FTPReplyError, error.FTPTempError, error.FTPPermError, error.FTPProtoError }");
}

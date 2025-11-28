/// Python imaplib module - IMAP4 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate imaplib.IMAP4 class
pub fn genIMAP4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 143), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }");
}

/// Generate imaplib.IMAP4_SSL class
pub fn genIMAP4_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 993), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }");
}

/// Generate imaplib.IMAP4_stream class
pub fn genIMAP4_stream(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .state = \"LOGOUT\" }");
}

// ============================================================================
// Port constants
// ============================================================================

pub fn genIMAP4_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 143)");
}

pub fn genIMAP4_SSL_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 993)");
}

// ============================================================================
// Commands mapping
// ============================================================================

pub fn genCommands(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

// ============================================================================
// Response codes
// ============================================================================

pub fn genOK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"OK\"");
}

pub fn genNO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"NO\"");
}

pub fn genBAD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BAD\"");
}

pub fn genBYE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BYE\"");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genIMAP4_error(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IMAP4Error");
}

pub fn genIMAP4_abort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IMAP4Abort");
}

pub fn genIMAP4_readonly(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IMAP4Readonly");
}

// ============================================================================
// Utility functions
// ============================================================================

/// Generate imaplib.Internaldate2tuple(datestr)
pub fn genInternaldate2tuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate imaplib.Int2AP(num)
pub fn genInt2AP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate imaplib.ParseFlags(data)
pub fn genParseFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate imaplib.Time2Internaldate(date_time)
pub fn genTime2Internaldate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

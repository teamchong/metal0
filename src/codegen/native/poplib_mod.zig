/// Python poplib module - POP3 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate poplib.POP3 class
pub fn genPOP3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 110), .timeout = @as(f64, -1.0) }");
}

/// Generate poplib.POP3_SSL class
pub fn genPOP3_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .host = \"\", .port = @as(i32, 995), .timeout = @as(f64, -1.0) }");
}

// ============================================================================
// Port constants
// ============================================================================

pub fn genPOP3_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 110)");
}

pub fn genPOP3_SSL_PORT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 995)");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genError_proto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.POP3ProtoError");
}

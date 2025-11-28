/// Python cgi module - CGI utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate cgi.parse(fp=None, environ=os.environ, ...)
pub fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate cgi.parse_qs(qs, keep_blank_values=False, ...)
pub fn genParse_qs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate cgi.parse_qsl(qs, keep_blank_values=False, ...)
pub fn genParse_qsl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_].{ []const u8, []const u8 }{}");
}

/// Generate cgi.parse_multipart(fp, pdict)
pub fn genParse_multipart(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate cgi.parse_header(line)
pub fn genParse_header(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", .{} }");
}

/// Generate cgi.test() - test CGI setup
pub fn genTest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgi.print_environ() - print environment
pub fn genPrint_environ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgi.print_form(form) - print form data
pub fn genPrint_form(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgi.print_directory() - print directory listing
pub fn genPrint_directory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgi.print_environ_usage() - print usage info
pub fn genPrint_environ_usage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate cgi.escape(s, quote=False) - deprecated HTML escape
pub fn genEscape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

// ============================================================================
// FieldStorage class
// ============================================================================

/// Generate cgi.FieldStorage class
pub fn genFieldStorage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = @as(?[]const u8, null), .filename = @as(?[]const u8, null), .value = @as(?[]const u8, null), .file = @as(?*anyopaque, null), .type = \"text/plain\", .type_options = .{}, .disposition = @as(?[]const u8, null), .disposition_options = .{}, .headers = .{}, .list = @as(?*anyopaque, null) }");
}

/// Generate cgi.MiniFieldStorage class
pub fn genMiniFieldStorage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = @as(?[]const u8, null), .value = @as(?[]const u8, null) }");
}

// ============================================================================
// Constants
// ============================================================================

pub fn genMaxlen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)"); // 0 means unlimited
}

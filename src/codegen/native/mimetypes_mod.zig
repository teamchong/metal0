/// Python mimetypes module - MIME type mapping
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate mimetypes.guess_type(url, strict=True)
pub fn genGuess_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(?[]const u8, null), @as(?[]const u8, null) }");
}

/// Generate mimetypes.guess_all_extensions(type, strict=True)
pub fn genGuess_all_extensions(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate mimetypes.guess_extension(type, strict=True)
pub fn genGuess_extension(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate mimetypes.init(files=None)
pub fn genInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate mimetypes.read_mime_types(filename)
pub fn genRead_mime_types(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(.{}), null)");
}

/// Generate mimetypes.add_type(type, ext, strict=True)
pub fn genAdd_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate mimetypes.MimeTypes class
pub fn genMimeTypes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .encodings_map = .{}, .suffix_map = .{}, .types_map = .{ .{}, .{} }, .types_map_inv = .{ .{}, .{} } }");
}

// ============================================================================
// Data attributes
// ============================================================================

pub fn genKnownfiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"/etc/mime.types\", \"/etc/httpd/mime.types\", \"/etc/httpd/conf/mime.types\", \"/etc/apache/mime.types\", \"/etc/apache2/mime.types\", \"/usr/local/etc/httpd/conf/mime.types\", \"/usr/local/lib/netscape/mime.types\", \"/usr/local/etc/mime.types\" }");
}

pub fn genInited(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

pub fn genSuffix_map(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genEncodings_map(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genTypes_map(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

pub fn genCommon_types(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

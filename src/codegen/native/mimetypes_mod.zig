/// Python mimetypes module - MIME type mapping
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "guess_type", genGuess_type }, .{ "guess_all_extensions", genGuess_all_extensions },
    .{ "guess_extension", genGuess_extension }, .{ "init", genUnit }, .{ "read_mime_types", genReadNull },
    .{ "add_type", genUnit }, .{ "MimeTypes", genMimeTypes }, .{ "knownfiles", genKnownfiles },
    .{ "inited", genFalse }, .{ "suffix_map", genEmpty }, .{ "encodings_map", genEmpty },
    .{ "types_map", genEmpty }, .{ "common_types", genEmpty },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genReadNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(.{}), null)"); }
fn genGuess_type(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(?[]const u8, null), @as(?[]const u8, null) }"); }
fn genGuess_all_extensions(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genGuess_extension(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genMimeTypes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .encodings_map = .{}, .suffix_map = .{}, .types_map = .{ .{}, .{} }, .types_map_inv = .{ .{}, .{} } }"); }
fn genKnownfiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"/etc/mime.types\", \"/etc/httpd/mime.types\", \"/etc/httpd/conf/mime.types\", \"/etc/apache/mime.types\", \"/etc/apache2/mime.types\", \"/usr/local/etc/httpd/conf/mime.types\", \"/usr/local/lib/netscape/mime.types\", \"/usr/local/etc/mime.types\" }"); }

/// Python mimetypes module - MIME type mapping
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "guess_type", genConst(".{ @as(?[]const u8, null), @as(?[]const u8, null) }") },
    .{ "guess_all_extensions", genConst("&[_][]const u8{}") },
    .{ "guess_extension", genConst("@as(?[]const u8, null)") },
    .{ "init", genConst("{}") }, .{ "read_mime_types", genConst("@as(?@TypeOf(.{}), null)") },
    .{ "add_type", genConst("{}") },
    .{ "MimeTypes", genConst(".{ .encodings_map = .{}, .suffix_map = .{}, .types_map = .{ .{}, .{} }, .types_map_inv = .{ .{}, .{} } }") },
    .{ "knownfiles", genConst("&[_][]const u8{ \"/etc/mime.types\", \"/etc/httpd/mime.types\", \"/etc/httpd/conf/mime.types\", \"/etc/apache/mime.types\", \"/etc/apache2/mime.types\", \"/usr/local/etc/httpd/conf/mime.types\", \"/usr/local/lib/netscape/mime.types\", \"/usr/local/etc/mime.types\" }") },
    .{ "inited", genConst("false") }, .{ "suffix_map", genConst(".{}") }, .{ "encodings_map", genConst(".{}") },
    .{ "types_map", genConst(".{}") }, .{ "common_types", genConst(".{}") },
});

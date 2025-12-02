/// Python mimetypes module - MIME type mapping
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "guess_type", h.c(".{ @as(?[]const u8, null), @as(?[]const u8, null) }") },
    .{ "guess_all_extensions", h.c("&[_][]const u8{}") },
    .{ "guess_extension", h.c("@as(?[]const u8, null)") },
    .{ "init", h.c("{}") }, .{ "read_mime_types", h.c("@as(?@TypeOf(.{}), null)") },
    .{ "add_type", h.c("{}") },
    .{ "MimeTypes", h.c(".{ .encodings_map = .{}, .suffix_map = .{}, .types_map = .{ .{}, .{} }, .types_map_inv = .{ .{}, .{} } }") },
    .{ "knownfiles", h.c("&[_][]const u8{ \"/etc/mime.types\", \"/etc/httpd/mime.types\", \"/etc/httpd/conf/mime.types\", \"/etc/apache/mime.types\", \"/etc/apache2/mime.types\", \"/usr/local/etc/httpd/conf/mime.types\", \"/usr/local/lib/netscape/mime.types\", \"/usr/local/etc/mime.types\" }") },
    .{ "inited", h.c("false") }, .{ "suffix_map", h.c(".{}") }, .{ "encodings_map", h.c(".{}") },
    .{ "types_map", h.c(".{}") }, .{ "common_types", h.c(".{}") },
});

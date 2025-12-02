/// Python cgi module - CGI utilities
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", h.c(".{}") }, .{ "parse_qs", h.c(".{}") }, .{ "parse_multipart", h.c(".{}") },
    .{ "parse_qsl", h.c("&[_].{ []const u8, []const u8 }{}") }, .{ "parse_header", h.c(".{ \"\", .{} }") },
    .{ "test", h.c("{}") }, .{ "print_environ", h.c("{}") }, .{ "print_form", h.c("{}") },
    .{ "print_directory", h.c("{}") }, .{ "print_environ_usage", h.c("{}") },
    .{ "escape", h.pass("\"\"") }, .{ "FieldStorage", h.c(".{ .name = @as(?[]const u8, null), .filename = @as(?[]const u8, null), .value = @as(?[]const u8, null), .file = @as(?*anyopaque, null), .type = \"text/plain\", .type_options = .{}, .disposition = @as(?[]const u8, null), .disposition_options = .{}, .headers = .{}, .list = @as(?*anyopaque, null) }") },
    .{ "MiniFieldStorage", h.c(".{ .name = @as(?[]const u8, null), .value = @as(?[]const u8, null) }") },
    .{ "maxlen", h.I64(0) },
});

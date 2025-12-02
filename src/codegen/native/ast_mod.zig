/// Python ast module - Abstract Syntax Trees
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", h.c("@as(?*anyopaque, null)") }, .{ "literal_eval", h.c("@as(?*anyopaque, null)") },
    .{ "fix_missing_locations", h.c("@as(?*anyopaque, null)") }, .{ "increment_lineno", h.c("@as(?*anyopaque, null)") },
    .{ "copy_location", h.c("@as(?*anyopaque, null)") }, .{ "dump", h.c("\"\"") }, .{ "unparse", h.c("\"\"") },
    .{ "get_docstring", h.c("null") }, .{ "get_source_segment", h.c("null") },
    .{ "iter_fields", h.c("&[_]struct { name: []const u8, value: *anyopaque }{}") },
    .{ "iter_child_nodes", h.c("&[_]*anyopaque{}") }, .{ "walk", h.c("&[_]*anyopaque{}") },
    .{ "AST", h.c(".{}") }, .{ "NodeVisitor", h.c(".{}") }, .{ "NodeTransformer", h.c(".{}") },
    .{ "Module", h.c(".{ .body = &[_]*anyopaque{}, .type_ignores = &[_]*anyopaque{} }") },
    .{ "Expression", h.c(".{ .body = @as(?*anyopaque, null) }") },
    .{ "Interactive", h.c(".{ .body = &[_]*anyopaque{} }") },
    .{ "FunctionDef", h.c(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }") },
    .{ "AsyncFunctionDef", h.c(".{ .name = \"\", .args = @as(?*anyopaque, null), .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{}, .returns = @as(?*anyopaque, null) }") },
    .{ "ClassDef", h.c(".{ .name = \"\", .bases = &[_]*anyopaque{}, .keywords = &[_]*anyopaque{}, .body = &[_]*anyopaque{}, .decorator_list = &[_]*anyopaque{} }") },
    .{ "Return", h.c(".{ .value = @as(?*anyopaque, null) }") },
    .{ "Name", h.c(".{ .id = \"\", .ctx = @as(?*anyopaque, null) }") },
    .{ "Constant", h.c(".{ .value = @as(?*anyopaque, null), .kind = @as(?[]const u8, null) }") },
    .{ "PyCF_ONLY_AST", h.hex32(0x400) }, .{ "PyCF_TYPE_COMMENTS", h.hex32(0x1000) },
});

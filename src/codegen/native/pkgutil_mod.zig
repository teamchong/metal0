/// Python pkgutil module - Package utilities
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "extend_path", h.pass("&[_][]const u8{}") }, .{ "find_loader", h.c("@as(?*anyopaque, null)") },
    .{ "get_importer", h.c("@as(?*anyopaque, null)") }, .{ "get_loader", h.c("@as(?*anyopaque, null)") },
    .{ "iter_importers", h.c("&[_]*anyopaque{}") },
    .{ "iter_modules", h.c("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "walk_packages", h.c("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "get_data", h.c("@as(?[]const u8, null)") }, .{ "resolve_name", h.c("@as(?*anyopaque, null)") },
    .{ "ModuleInfo", h.c(".{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }") },
    .{ "ImpImporter", h.c(".{}") }, .{ "ImpLoader", h.c(".{}") },
});

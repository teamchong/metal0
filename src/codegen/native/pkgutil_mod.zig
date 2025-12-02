/// Python pkgutil module - Package utilities
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "extend_path", genExtendPath }, .{ "find_loader", h.c("@as(?*anyopaque, null)") },
    .{ "get_importer", h.c("@as(?*anyopaque, null)") }, .{ "get_loader", h.c("@as(?*anyopaque, null)") },
    .{ "iter_importers", h.c("&[_]*anyopaque{}") },
    .{ "iter_modules", h.c("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "walk_packages", h.c("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "get_data", h.c("@as(?[]const u8, null)") }, .{ "resolve_name", h.c("@as(?*anyopaque, null)") },
    .{ "ModuleInfo", h.c(".{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }") },
    .{ "ImpImporter", h.c(".{}") }, .{ "ImpLoader", h.c(".{}") },
});

fn genExtendPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("&[_][]const u8{}");
}

/// Python pkgutil module - Package utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "extend_path", genExtendPath }, .{ "find_loader", genConst("@as(?*anyopaque, null)") },
    .{ "get_importer", genConst("@as(?*anyopaque, null)") }, .{ "get_loader", genConst("@as(?*anyopaque, null)") },
    .{ "iter_importers", genConst("&[_]*anyopaque{}") },
    .{ "iter_modules", genConst("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "walk_packages", genConst("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}") },
    .{ "get_data", genConst("@as(?[]const u8, null)") }, .{ "resolve_name", genConst("@as(?*anyopaque, null)") },
    .{ "ModuleInfo", genConst(".{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }") },
    .{ "ImpImporter", genConst(".{}") }, .{ "ImpLoader", genConst(".{}") },
});

fn genExtendPath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("&[_][]const u8{}");
}

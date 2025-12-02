/// Python pkgutil module - Package utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "extend_path", genExtend_path }, .{ "find_loader", genNullPtr }, .{ "get_importer", genNullPtr },
    .{ "get_loader", genNullPtr }, .{ "iter_importers", genEmptyPtrArr }, .{ "iter_modules", genModuleInfoArr },
    .{ "walk_packages", genModuleInfoArr }, .{ "get_data", genNullStr }, .{ "resolve_name", genNullPtr },
    .{ "ModuleInfo", genModuleInfo }, .{ "ImpImporter", genEmpty }, .{ "ImpLoader", genEmpty },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genNullStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?[]const u8, null)"); }
fn genEmptyPtrArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]*anyopaque{}"); }
fn genModuleInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }"); }
fn genModuleInfoArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}"); }

fn genExtend_path(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else try self.emit("&[_][]const u8{}");
}

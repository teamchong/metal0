/// Python modulefinder module - Find modules used by a script
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genModuleFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .modules = .{}, .badmodules = .{}, .debug = 0, .indent = 0, .excludes = &[_][]const u8{}, .replace_paths = &[_]struct { []const u8, []const u8 }{} }"); }
fn genFindHeadPackage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ null, \"\" }"); }
fn genScanOpcodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genAnyMissing(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genAnyMissingMaybe(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ &[_][]const u8{}, .{} }"); }
fn genModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .__name__ = \"\", .__file__ = null, .__path__ = null, .__code__ = null, .globalnames = .{}, .starimports = .{} }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ModuleFinder", genModuleFinder }, .{ "msg", genUnit }, .{ "msgin", genUnit }, .{ "msgout", genUnit },
    .{ "run_script", genUnit }, .{ "load_file", genUnit }, .{ "import_hook", genNull },
    .{ "determine_parent", genNull }, .{ "find_head_package", genFindHeadPackage },
    .{ "load_tail", genNull }, .{ "ensure_fromlist", genUnit }, .{ "find_all_submodules", genUnit },
    .{ "import_module", genNull }, .{ "load_module", genNull }, .{ "scan_code", genUnit },
    .{ "scan_opcodes", genScanOpcodes }, .{ "any_missing", genAnyMissing },
    .{ "any_missing_maybe", genAnyMissingMaybe }, .{ "replace_paths_in_code", genReplacePathsInCode },
    .{ "report", genUnit }, .{ "Module", genModule }, .{ "ReplacePackage", genUnit }, .{ "AddPackagePath", genUnit },
});

fn genReplacePathsInCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); }
}

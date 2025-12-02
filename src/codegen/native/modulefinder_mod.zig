/// Python modulefinder module - Find modules used by a script
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ModuleFinder", genConst(".{ .modules = .{}, .badmodules = .{}, .debug = 0, .indent = 0, .excludes = &[_][]const u8{}, .replace_paths = &[_]struct { []const u8, []const u8 }{} }") },
    .{ "msg", genConst("{}") }, .{ "msgin", genConst("{}") }, .{ "msgout", genConst("{}") },
    .{ "run_script", genConst("{}") }, .{ "load_file", genConst("{}") }, .{ "import_hook", genConst("null") },
    .{ "determine_parent", genConst("null") }, .{ "find_head_package", genConst(".{ null, \"\" }") },
    .{ "load_tail", genConst("null") }, .{ "ensure_fromlist", genConst("{}") }, .{ "find_all_submodules", genConst("{}") },
    .{ "import_module", genConst("null") }, .{ "load_module", genConst("null") }, .{ "scan_code", genConst("{}") },
    .{ "scan_opcodes", genConst("&[_]@TypeOf(.{}){}") }, .{ "any_missing", genConst("&[_][]const u8{}") },
    .{ "any_missing_maybe", genConst(".{ &[_][]const u8{}, .{} }") }, .{ "replace_paths_in_code", genReplacePathsInCode },
    .{ "report", genConst("{}") },
    .{ "Module", genConst(".{ .__name__ = \"\", .__file__ = null, .__path__ = null, .__code__ = null, .globalnames = .{}, .starimports = .{} }") },
    .{ "ReplacePackage", genConst("{}") }, .{ "AddPackagePath", genConst("{}") },
});

fn genReplacePathsInCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); }
}

/// Python modulefinder module - Find modules used by a script
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ModuleFinder", h.c(".{ .modules = .{}, .badmodules = .{}, .debug = 0, .indent = 0, .excludes = &[_][]const u8{}, .replace_paths = &[_]struct { []const u8, []const u8 }{} }") },
    .{ "msg", h.c("{}") }, .{ "msgin", h.c("{}") }, .{ "msgout", h.c("{}") },
    .{ "run_script", h.c("{}") }, .{ "load_file", h.c("{}") }, .{ "import_hook", h.c("null") },
    .{ "determine_parent", h.c("null") }, .{ "find_head_package", h.c(".{ null, \"\" }") },
    .{ "load_tail", h.c("null") }, .{ "ensure_fromlist", h.c("{}") }, .{ "find_all_submodules", h.c("{}") },
    .{ "import_module", h.c("null") }, .{ "load_module", h.c("null") }, .{ "scan_code", h.c("{}") },
    .{ "scan_opcodes", h.c("&[_]@TypeOf(.{}){}") }, .{ "any_missing", h.c("&[_][]const u8{}") },
    .{ "any_missing_maybe", h.c(".{ &[_][]const u8{}, .{} }") }, .{ "replace_paths_in_code", genReplacePathsInCode },
    .{ "report", h.c("{}") },
    .{ "Module", h.c(".{ .__name__ = \"\", .__file__ = null, .__path__ = null, .__code__ = null, .globalnames = .{}, .starimports = .{} }") },
    .{ "ReplacePackage", h.c("{}") }, .{ "AddPackagePath", h.c("{}") },
});

fn genReplacePathsInCode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("null"); }
}

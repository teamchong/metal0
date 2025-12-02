/// Python importlib module - Import system utilities
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const module_spec = ".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }";
const module_type = ".{ .__name__ = \"\", .__doc__ = @as(?[]const u8, null), .__package__ = @as(?[]const u8, null), .__loader__ = @as(?*anyopaque, null), .__spec__ = @as(?*anyopaque, null) }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ModuleSpec", h.c(module_spec) }, .{ "BuiltinImporter", h.c(".{}") }, .{ "FrozenImporter", h.c(".{}") },
    .{ "PathFinder", h.c(".{}") }, .{ "FileFinder", h.c(".{}") }, .{ "SourceFileLoader", h.c(".{}") },
    .{ "SourcelessFileLoader", h.c(".{}") }, .{ "ExtensionFileLoader", h.c(".{}") },
    .{ "SOURCE_SUFFIXES", h.c("&[_][]const u8{\".py\"}") }, .{ "BYTECODE_SUFFIXES", h.c("&[_][]const u8{\".pyc\"}") },
    .{ "EXTENSION_SUFFIXES", h.c("&[_][]const u8{\".so\", \".pyd\"}") }, .{ "all_suffixes", h.c("&[_][]const u8{\".py\", \".pyc\", \".so\", \".pyd\"}") },
    .{ "import_module", h.c("@as(?*anyopaque, null)") }, .{ "reload", genReload }, .{ "invalidate_caches", h.c("{}") },
    .{ "Loader", h.c(".{}") }, .{ "MetaPathFinder", h.c(".{}") }, .{ "PathEntryFinder", h.c(".{}") },
    .{ "ResourceLoader", h.c(".{}") }, .{ "InspectLoader", h.c(".{}") }, .{ "ExecutionLoader", h.c(".{}") },
    .{ "FileLoader", h.c(".{}") }, .{ "SourceLoader", h.c(".{}") }, .{ "Traversable", h.c(".{}") },
    .{ "TraversableResources", h.c(".{}") }, .{ "files", h.c(".{}") }, .{ "as_file", h.c(".{}") },
    .{ "read_text", h.c("\"\"") }, .{ "read_binary", h.c("\"\"") }, .{ "is_resource", h.c("false") },
    .{ "contents", h.c("&[_][]const u8{}") }, .{ "version", h.c("\"0.0.0\"") }, .{ "metadata", h.c(".{}") },
    .{ "entry_points", h.c(".{}") }, .{ "requires", h.c("@as(?@TypeOf(&[_][]const u8{}), null)") },
    .{ "distributions", h.c("&[_]@TypeOf(.{ .name = \"\", .version = \"0.0.0\" }){}") },
    .{ "packages_distributions", h.c(".{}") }, .{ "PackageNotFoundError", h.err("PackageNotFoundError") },
    .{ "find_spec", h.c("@as(?@TypeOf(" ++ module_spec ++ "), null)") }, .{ "module_from_spec", h.c(module_type) },
    .{ "spec_from_loader", h.c(module_spec) },
    .{ "spec_from_file_location", h.c(".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = true }") },
    .{ "source_hash", h.c("\"\"") }, .{ "resolve_name", genResolve_name }, .{ "LazyLoader", h.c(".{}") },
    .{ "MAGIC_NUMBER", h.c("\"\\x61\\x0d\\x0d\\x0a\"") }, .{ "cache_from_source", h.c("\"\"") },
    .{ "source_from_cache", h.c("\"\"") }, .{ "decode_source", h.c("\"\"") },
});

fn genReload(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
fn genResolve_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

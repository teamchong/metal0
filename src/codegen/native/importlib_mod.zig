/// Python importlib module - Import system utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

const module_spec = ".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }";
const module_type = ".{ .__name__ = \"\", .__doc__ = @as(?[]const u8, null), .__package__ = @as(?[]const u8, null), .__loader__ = @as(?*anyopaque, null), .__spec__ = @as(?*anyopaque, null) }";

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ModuleSpec", genConst(module_spec) }, .{ "BuiltinImporter", genConst(".{}") }, .{ "FrozenImporter", genConst(".{}") },
    .{ "PathFinder", genConst(".{}") }, .{ "FileFinder", genConst(".{}") }, .{ "SourceFileLoader", genConst(".{}") },
    .{ "SourcelessFileLoader", genConst(".{}") }, .{ "ExtensionFileLoader", genConst(".{}") },
    .{ "SOURCE_SUFFIXES", genConst("&[_][]const u8{\".py\"}") }, .{ "BYTECODE_SUFFIXES", genConst("&[_][]const u8{\".pyc\"}") },
    .{ "EXTENSION_SUFFIXES", genConst("&[_][]const u8{\".so\", \".pyd\"}") }, .{ "all_suffixes", genConst("&[_][]const u8{\".py\", \".pyc\", \".so\", \".pyd\"}") },
    .{ "import_module", genConst("@as(?*anyopaque, null)") }, .{ "reload", genReload }, .{ "invalidate_caches", genConst("{}") },
    .{ "Loader", genConst(".{}") }, .{ "MetaPathFinder", genConst(".{}") }, .{ "PathEntryFinder", genConst(".{}") },
    .{ "ResourceLoader", genConst(".{}") }, .{ "InspectLoader", genConst(".{}") }, .{ "ExecutionLoader", genConst(".{}") },
    .{ "FileLoader", genConst(".{}") }, .{ "SourceLoader", genConst(".{}") }, .{ "Traversable", genConst(".{}") },
    .{ "TraversableResources", genConst(".{}") }, .{ "files", genConst(".{}") }, .{ "as_file", genConst(".{}") },
    .{ "read_text", genConst("\"\"") }, .{ "read_binary", genConst("\"\"") }, .{ "is_resource", genConst("false") },
    .{ "contents", genConst("&[_][]const u8{}") }, .{ "version", genConst("\"0.0.0\"") }, .{ "metadata", genConst(".{}") },
    .{ "entry_points", genConst(".{}") }, .{ "requires", genConst("@as(?@TypeOf(&[_][]const u8{}), null)") },
    .{ "distributions", genConst("&[_]@TypeOf(.{ .name = \"\", .version = \"0.0.0\" }){}") },
    .{ "packages_distributions", genConst(".{}") }, .{ "PackageNotFoundError", genConst("error.PackageNotFoundError") },
    .{ "find_spec", genConst("@as(?@TypeOf(" ++ module_spec ++ "), null)") }, .{ "module_from_spec", genConst(module_type) },
    .{ "spec_from_loader", genConst(module_spec) },
    .{ "spec_from_file_location", genConst(".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = true }") },
    .{ "source_hash", genConst("\"\"") }, .{ "resolve_name", genResolve_name }, .{ "LazyLoader", genConst(".{}") },
    .{ "MAGIC_NUMBER", genConst("\"\\x61\\x0d\\x0d\\x0a\"") }, .{ "cache_from_source", genConst("\"\"") },
    .{ "source_from_cache", genConst("\"\"") }, .{ "decode_source", genConst("\"\"") },
});

fn genReload(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
fn genResolve_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

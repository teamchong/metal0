/// Python importlib module - Import system utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ModuleSpec", genModuleSpec }, .{ "BuiltinImporter", genEmpty }, .{ "FrozenImporter", genEmpty },
    .{ "PathFinder", genEmpty }, .{ "FileFinder", genEmpty }, .{ "SourceFileLoader", genEmpty },
    .{ "SourcelessFileLoader", genEmpty }, .{ "ExtensionFileLoader", genEmpty },
    .{ "SOURCE_SUFFIXES", genSOURCE_SUFFIXES }, .{ "BYTECODE_SUFFIXES", genBYTECODE_SUFFIXES },
    .{ "EXTENSION_SUFFIXES", genEXTENSION_SUFFIXES }, .{ "all_suffixes", genAll_suffixes },
    .{ "import_module", genNullPtr }, .{ "reload", genReload }, .{ "invalidate_caches", genUnit },
    .{ "Loader", genEmpty }, .{ "MetaPathFinder", genEmpty }, .{ "PathEntryFinder", genEmpty },
    .{ "ResourceLoader", genEmpty }, .{ "InspectLoader", genEmpty }, .{ "ExecutionLoader", genEmpty },
    .{ "FileLoader", genEmpty }, .{ "SourceLoader", genEmpty }, .{ "Traversable", genEmpty },
    .{ "TraversableResources", genEmpty }, .{ "files", genEmpty }, .{ "as_file", genEmpty },
    .{ "read_text", genEmptyStr }, .{ "read_binary", genEmptyStr }, .{ "is_resource", genFalse },
    .{ "contents", genEmptyStrSlice }, .{ "version", genVersion }, .{ "metadata", genEmpty },
    .{ "entry_points", genEmpty }, .{ "requires", genNullStrSlice }, .{ "distributions", genEmptyDists },
    .{ "packages_distributions", genEmpty }, .{ "PackageNotFoundError", genPackageNotFoundError },
    .{ "find_spec", genNullSpec }, .{ "module_from_spec", genModule },
    .{ "spec_from_loader", genSpec }, .{ "spec_from_file_location", genSpecWithLoc },
    .{ "source_hash", genEmptyStr }, .{ "resolve_name", genResolve_name }, .{ "LazyLoader", genEmpty },
    .{ "MAGIC_NUMBER", genMAGIC_NUMBER }, .{ "cache_from_source", genEmptyStr },
    .{ "source_from_cache", genEmptyStr }, .{ "decode_source", genEmptyStr },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmptyStrSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genNullStrSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(&[_][]const u8{}), null)"); }

// Specific types
fn genSOURCE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{\".py\"}"); }
fn genBYTECODE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{\".pyc\"}"); }
fn genEXTENSION_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{\".so\", \".pyd\"}"); }
fn genAll_suffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{\".py\", \".pyc\", \".so\", \".pyd\"}"); }
fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"0.0.0\""); }
fn genEmptyDists(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{ .name = \"\", .version = \"0.0.0\" }){}"); }
fn genPackageNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.PackageNotFoundError"); }
fn genMAGIC_NUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x61\\x0d\\x0d\\x0a\""); }

// Spec types
fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }"); }
fn genNullSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?@TypeOf(.{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }), null)"); }
fn genModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .__name__ = \"\", .__doc__ = @as(?[]const u8, null), .__package__ = @as(?[]const u8, null), .__loader__ = @as(?*anyopaque, null), .__spec__ = @as(?*anyopaque, null) }"); }
fn genSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }"); }
fn genSpecWithLoc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = true }"); }

// Dynamic funcs
fn genReload(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
fn genResolve_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

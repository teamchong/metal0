/// Python importlib module - Import system utilities
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ModuleSpec", genModuleSpec },
    .{ "BuiltinImporter", genBuiltinImporter },
    .{ "FrozenImporter", genFrozenImporter },
    .{ "PathFinder", genPathFinder },
    .{ "FileFinder", genFileFinder },
    .{ "SourceFileLoader", genSourceFileLoader },
    .{ "SourcelessFileLoader", genSourcelessFileLoader },
    .{ "ExtensionFileLoader", genExtensionFileLoader },
    .{ "SOURCE_SUFFIXES", genSOURCE_SUFFIXES },
    .{ "BYTECODE_SUFFIXES", genBYTECODE_SUFFIXES },
    .{ "EXTENSION_SUFFIXES", genEXTENSION_SUFFIXES },
    .{ "all_suffixes", genAll_suffixes },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Note: Dynamic imports are limited in AOT compilation
// These provide stub implementations for common patterns

/// Generate importlib.import_module(name, package=None) - AOT limited
pub fn genImport_module(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // AOT compilation resolves imports at compile time
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate importlib.reload(module) - AOT limited
pub fn genReload(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate importlib.invalidate_caches()
pub fn genInvalidate_caches(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// importlib.abc - Abstract base classes
// ============================================================================

/// Generate importlib.abc.Loader
pub fn genLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.MetaPathFinder
pub fn genMetaPathFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.PathEntryFinder
pub fn genPathEntryFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.ResourceLoader
pub fn genResourceLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.InspectLoader
pub fn genInspectLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.ExecutionLoader
pub fn genExecutionLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.FileLoader
pub fn genFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.SourceLoader
pub fn genSourceLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.Traversable
pub fn genTraversable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.abc.TraversableResources
pub fn genTraversableResources(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// importlib.resources - Resource access
// ============================================================================

/// Generate importlib.resources.files(package)
pub fn genFiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.resources.as_file(traversable)
pub fn genAs_file(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.resources.read_text(package, resource, encoding='utf-8', errors='strict')
pub fn genRead_text(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate importlib.resources.read_binary(package, resource)
pub fn genRead_binary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate importlib.resources.is_resource(package, name)
pub fn genIs_resource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate importlib.resources.contents(package)
pub fn genContents(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

// ============================================================================
// importlib.metadata - Package metadata
// ============================================================================

/// Generate importlib.metadata.version(distribution_name)
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0.0.0\"");
}

/// Generate importlib.metadata.metadata(distribution_name)
pub fn genMetadata(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.metadata.entry_points(*, group=None, name=None, ...)
pub fn genEntry_points(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.metadata.files(distribution_name)
pub fn genMetadataFiles(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(&[_]@TypeOf(.{ .name = \"\", .hash = @as(?[]const u8, null), .size = @as(?i64, null) }){}), null)");
}

/// Generate importlib.metadata.requires(distribution_name)
pub fn genRequires(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(&[_][]const u8{}), null)");
}

/// Generate importlib.metadata.distributions()
pub fn genDistributions(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .name = \"\", .version = \"0.0.0\" }){}");
}

/// Generate importlib.metadata.packages_distributions()
pub fn genPackages_distributions(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.metadata.PackageNotFoundError
pub fn genPackageNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PackageNotFoundError");
}

// ============================================================================
// importlib.util - Utility code
// ============================================================================

/// Generate importlib.util.find_spec(name, package=None)
pub fn genFind_spec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?@TypeOf(.{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }), null)");
}

/// Generate importlib.util.module_from_spec(spec)
pub fn genModule_from_spec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .__name__ = \"\", .__doc__ = @as(?[]const u8, null), .__package__ = @as(?[]const u8, null), .__loader__ = @as(?*anyopaque, null), .__spec__ = @as(?*anyopaque, null) }");
}

/// Generate importlib.util.spec_from_loader(name, loader, *, origin=None, is_package=None)
pub fn genSpec_from_loader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }");
}

/// Generate importlib.util.spec_from_file_location(name, location=None, *, loader=None, submodule_search_locations=None)
pub fn genSpec_from_file_location(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = true }");
}

/// Generate importlib.util.source_hash(source_bytes)
pub fn genSource_hash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate importlib.util.resolve_name(name, package)
pub fn genResolve_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate importlib.util.LazyLoader
pub fn genLazyLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.util.MAGIC_NUMBER
pub fn genMAGIC_NUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x61\\x0d\\x0d\\x0a\""); // Python 3.11 magic
}

/// Generate importlib.util.cache_from_source(path, debug_override=None, *, optimization=None)
pub fn genCache_from_source(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate importlib.util.source_from_cache(path)
pub fn genSource_from_cache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate importlib.util.decode_source(source_bytes)
pub fn genDecode_source(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

// ============================================================================
// importlib.machinery - Import system components
// ============================================================================

/// Generate importlib.machinery.ModuleSpec
pub fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .loader = @as(?*anyopaque, null), .origin = @as(?[]const u8, null), .submodule_search_locations = @as(?*anyopaque, null), .cached = @as(?[]const u8, null), .parent = @as(?[]const u8, null), .has_location = false }");
}

/// Generate importlib.machinery.BuiltinImporter
pub fn genBuiltinImporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.FrozenImporter
pub fn genFrozenImporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.PathFinder
pub fn genPathFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.FileFinder
pub fn genFileFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.SourceFileLoader
pub fn genSourceFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.SourcelessFileLoader
pub fn genSourcelessFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.ExtensionFileLoader
pub fn genExtensionFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate importlib.machinery.SOURCE_SUFFIXES
pub fn genSOURCE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\".py\"}");
}

/// Generate importlib.machinery.BYTECODE_SUFFIXES
pub fn genBYTECODE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\".pyc\"}");
}

/// Generate importlib.machinery.EXTENSION_SUFFIXES
pub fn genEXTENSION_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\".so\", \".pyd\"}");
}

/// Generate importlib.machinery.all_suffixes()
pub fn genAll_suffixes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{\".py\", \".pyc\", \".so\", \".pyd\"}");
}

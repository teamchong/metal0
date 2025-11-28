/// Python _frozen_importlib_external module - External frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _frozen_importlib_external.SourceFileLoader(fullname, path)
pub fn genSourceFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; const path = ");
        try self.genExpr(args[1]);
        try self.emit("; break :blk .{ .name = name, .path = path }; }");
    } else {
        try self.emit(".{ .name = \"\", .path = \"\" }");
    }
}

/// Generate _frozen_importlib_external.SourcelessFileLoader(fullname, path)
pub fn genSourcelessFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .path = \"\" }");
}

/// Generate _frozen_importlib_external.ExtensionFileLoader(name, path)
pub fn genExtensionFileLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .path = \"\" }");
}

/// Generate _frozen_importlib_external.FileFinder(path, *loader_details)
pub fn genFileFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .path = \"\", .loaders = &[_]@TypeOf(.{}){} }");
}

/// Generate _frozen_importlib_external.PathFinder class
pub fn genPathFinder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _frozen_importlib_external._get_supported_file_loaders()
pub fn genGetSupportedFileLoaders(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate _frozen_importlib_external._install(sys_module, _imp_module)
pub fn genInstall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _frozen_importlib_external.cache_from_source(path, debug_override=None, *, optimization=None)
pub fn genCacheFromSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = path; break :blk path; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate _frozen_importlib_external.source_from_cache(path)
pub fn genSourceFromCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = path; break :blk path; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate _frozen_importlib_external.spec_from_file_location(name, location=None, *, loader=None, submodule_search_locations=_POPULATE)
pub fn genSpecFromFileLocation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }");
}

/// Generate _frozen_importlib_external.BYTECODE_SUFFIXES constant
pub fn genBYTECODE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \".pyc\" }");
}

/// Generate _frozen_importlib_external.SOURCE_SUFFIXES constant
pub fn genSOURCE_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \".py\" }");
}

/// Generate _frozen_importlib_external.EXTENSION_SUFFIXES constant
pub fn genEXTENSION_SUFFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }");
}

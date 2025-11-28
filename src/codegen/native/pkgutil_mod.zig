/// Python pkgutil module - Package utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pkgutil.extend_path(path, name)
pub fn genExtend_path(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("&[_][]const u8{}");
    }
}

/// Generate pkgutil.find_loader(fullname, path=None)
pub fn genFind_loader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pkgutil.get_importer(path_item)
pub fn genGet_importer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pkgutil.get_loader(module_or_name)
pub fn genGet_loader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pkgutil.iter_importers(fullname='')
pub fn genIter_importers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*anyopaque{}");
}

/// Generate pkgutil.iter_modules(path=None, prefix='')
pub fn genIter_modules(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}");
}

/// Generate pkgutil.walk_packages(path=None, prefix='', onerror=None)
pub fn genWalk_packages(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }){}");
}

/// Generate pkgutil.get_data(package, resource)
pub fn genGet_data(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate pkgutil.resolve_name(name)
pub fn genResolve_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate pkgutil.ModuleInfo namedtuple
pub fn genModuleInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .module_finder = @as(?*anyopaque, null), .name = \"\", .ispkg = false }");
}

// ============================================================================
// Deprecated classes (for backwards compatibility)
// ============================================================================

/// Generate pkgutil.ImpImporter - deprecated
pub fn genImpImporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate pkgutil.ImpLoader - deprecated
pub fn genImpLoader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

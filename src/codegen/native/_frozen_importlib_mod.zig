/// Python _frozen_importlib module - Frozen import machinery
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _frozen_importlib.ModuleSpec(name, loader, *, origin=None, loader_state=None, is_package=None)
pub fn genModuleSpec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name, .loader = null, .origin = null, .submodule_search_locations = null }; }");
    } else {
        try self.emit(".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }");
    }
}

/// Generate _frozen_importlib.BuiltinImporter class
pub fn genBuiltinImporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _frozen_importlib.FrozenImporter class
pub fn genFrozenImporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _frozen_importlib._init_module_attrs(spec, module, *, override=False)
pub fn genInitModuleAttrs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _frozen_importlib._call_with_frames_removed(f, *args, **kwargs)
pub fn genCallWithFramesRemoved(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _frozen_importlib._find_and_load(name, import_)
pub fn genFindAndLoad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _frozen_importlib._find_and_load_unlocked(name, import_)
pub fn genFindAndLoadUnlocked(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _frozen_importlib._gcd_import(name, package=None, level=0)
pub fn genGcdImport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _frozen_importlib._handle_fromlist(module, fromlist, import_, *, recursive=False)
pub fn genHandleFromlist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _frozen_importlib._lock_unlock_module(name)
pub fn genLockUnlockModule(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _frozen_importlib.__import__(name, globals=None, locals=None, fromlist=(), level=0)
pub fn genImport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

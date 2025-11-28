/// Python _warnings module - Internal warnings support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _warnings.warn(message, category=UserWarning, stacklevel=1, source=None)
pub fn genWarn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _warnings.warn_explicit(message, category, filename, lineno, module=None, registry=None, module_globals=None, source=None)
pub fn genWarnExplicit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _warnings._filters_mutated()
pub fn genFiltersMutated(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _warnings.filters list
pub fn genFilters(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate _warnings._defaultaction constant
pub fn genDefaultaction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"default\"");
}

/// Generate _warnings._onceregistry dict
pub fn genOnceregistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

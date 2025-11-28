/// Python _py_abc module - Pure Python ABC implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _py_abc.ABCMeta class
pub fn genABCMeta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ ._abc_registry = .{}, ._abc_cache = .{}, ._abc_negative_cache = .{} }");
}

/// Generate _py_abc.get_cache_token()
pub fn genGetCacheToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

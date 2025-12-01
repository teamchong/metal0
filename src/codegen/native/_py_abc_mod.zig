/// Python _py_abc module - Pure Python ABC implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "a_b_c_meta", genABCMeta },
    .{ "get_cache_token", genGetCacheToken },
});

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

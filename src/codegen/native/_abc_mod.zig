/// Python _abc module - Internal ABC support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _abc.get_cache_token()
pub fn genGetCacheToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u64, 0)");
}

/// Generate _abc._abc_init(cls)
pub fn genAbcInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _abc._abc_register(cls, subclass)
pub fn genAbcRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("null");
    }
}

/// Generate _abc._abc_instancecheck(cls, instance)
pub fn genAbcInstancecheck(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _abc._abc_subclasscheck(cls, subclass)
pub fn genAbcSubclasscheck(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _abc._get_dump(cls)
pub fn genGetDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_]type{}, &[_]type{}, &[_]type{} }");
}

/// Generate _abc._reset_registry(cls)
pub fn genResetRegistry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _abc._reset_caches(cls)
pub fn genResetCaches(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

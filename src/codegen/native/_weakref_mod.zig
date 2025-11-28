/// Python _weakref module - Weak reference support (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _weakref.ref(object, callback=None)
pub fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const obj = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .ptr = @intFromPtr(&obj) }; }");
    } else {
        try self.emit(".{ .ptr = 0 }");
    }
}

/// Generate _weakref.proxy(object, callback=None)
pub fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
}

/// Generate _weakref.getweakrefcount(object)
pub fn genGetweakrefcount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _weakref.getweakrefs(object)
pub fn genGetweakrefs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate _weakref.CallableProxyType
pub fn genCallableProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

/// Generate _weakref.ProxyType
pub fn genProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

/// Generate _weakref.ReferenceType
pub fn genReferenceType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

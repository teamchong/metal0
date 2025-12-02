/// Python weakref module - Weak references
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ref", genRef },
    .{ "proxy", genProxy },
    .{ "getweakrefcount", genGetweakrefcount },
    .{ "getweakrefs", genGetweakrefs },
    .{ "WeakSet", genWeakSet },
    .{ "WeakKeyDictionary", genWeakKeyDictionary },
    .{ "WeakValueDictionary", genWeakValueDictionary },
    .{ "WeakMethod", genWeakMethod },
    .{ "finalize", genFinalize },
    .{ "ReferenceType", genReferenceType },
    .{ "ProxyType", genProxyType },
    .{ "CallableProxyType", genCallableProxyType },
});

/// Generate weakref.ref(object, callback=None) -> weak reference
pub fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }
    // Weak refs are just pointers in Zig - return address of object
    try self.emit("@as(?*anyopaque, @ptrCast(&");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// Generate weakref.proxy(object, callback=None) -> proxy object
pub fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Proxy returns the object directly in our implementation
    if (args.len == 0) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate weakref.getweakrefcount(object) -> int
pub fn genGetweakrefcount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Simplified - always return 0 (no weak ref tracking)
    try self.emit("@as(i64, 0)");
}

/// Generate weakref.getweakrefs(object) -> list
pub fn genGetweakrefs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return empty list
    try self.emit("&[_]*anyopaque{}");
}

/// Generate weakref.WeakSet() -> weak set
pub fn genWeakSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("items: std.ArrayList(*anyopaque) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn add(__self: *@This(), item: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.items.append(__global_allocator, @ptrCast(&item)) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn discard(__self: *@This(), item: anytype) void { _ = item; }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.items.items.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn __contains__(__self: *@This(), item: anytype) bool { _ = item; return false; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate weakref.WeakKeyDictionary() -> weak key dictionary
pub fn genWeakKeyDictionary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), key: anytype) ?[]const u8 { _ = key; return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn put(__self: *@This(), key: anytype, value: anytype) void { _ = key; _ = value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.data.count(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate weakref.WeakValueDictionary() -> weak value dictionary
pub fn genWeakValueDictionary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: hashmap_helper.StringHashMap(*anyopaque) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), key: []const u8) ?*anyopaque { return __self.data.get(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn put(__self: *@This(), key: []const u8, value: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self.data.put(key, @ptrCast(&value)) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.data.count(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate weakref.WeakMethod(method) -> weak method reference
pub fn genWeakMethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }
    try self.emit("@as(?*anyopaque, @ptrCast(&");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// Generate weakref.finalize(obj, func, *args, **kwargs) -> weak finalizer
pub fn genFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("alive: bool = true,\n");
    try self.emitIndent();
    try self.emit("pub fn __call__(__self: *@This()) void { __self.alive = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn detach(__self: *@This()) ?@This() { if (__self.alive) { __self.alive = false; return __self.*; } return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn peek(__self: *@This()) ?@This() { if (__self.alive) return __self.*; return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn atexit(__self: *@This()) bool { return __self.alive; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate weakref.ReferenceType constant
pub fn genReferenceType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"weakref\"");
}

/// Generate weakref.ProxyType constant
pub fn genProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"weakproxy\"");
}

/// Generate weakref.CallableProxyType constant
pub fn genCallableProxyType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"weakcallableproxy\"");
}

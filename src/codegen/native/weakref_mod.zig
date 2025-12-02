/// Python weakref module - Weak references
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ref", genRef }, .{ "proxy", genProxy },
    .{ "getweakrefcount", genConst("@as(i64, 0)") }, .{ "getweakrefs", genConst("&[_]*anyopaque{}") },
    .{ "WeakSet", genConst("struct { items: std.ArrayList(*anyopaque) = .{}, pub fn add(__self: *@This(), item: anytype) void { __self.items.append(__global_allocator, @ptrCast(&item)) catch {}; } pub fn discard(__self: *@This(), item: anytype) void { _ = item; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __contains__(__self: *@This(), item: anytype) bool { _ = item; return false; } }{}") },
    .{ "WeakKeyDictionary", genConst("struct { data: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), key: anytype) ?[]const u8 { _ = key; return null; } pub fn put(__self: *@This(), key: anytype, value: anytype) void { _ = key; _ = value; } pub fn __len__(__self: *@This()) usize { return __self.data.count(); } }{}") },
    .{ "WeakValueDictionary", genConst("struct { data: hashmap_helper.StringHashMap(*anyopaque) = .{}, pub fn get(__self: *@This(), key: []const u8) ?*anyopaque { return __self.data.get(key); } pub fn put(__self: *@This(), key: []const u8, value: anytype) void { __self.data.put(key, @ptrCast(&value)) catch {}; } pub fn __len__(__self: *@This()) usize { return __self.data.count(); } }{}") },
    .{ "WeakMethod", genRef },
    .{ "finalize", genConst("struct { alive: bool = true, pub fn __call__(__self: *@This()) void { __self.alive = false; } pub fn detach(__self: *@This()) ?@This() { if (__self.alive) { __self.alive = false; return __self.*; } return null; } pub fn peek(__self: *@This()) ?@This() { if (__self.alive) return __self.*; return null; } pub fn atexit(__self: *@This()) bool { return __self.alive; } }{}") },
    .{ "ReferenceType", genConst("\"weakref\"") }, .{ "ProxyType", genConst("\"weakproxy\"") },
    .{ "CallableProxyType", genConst("\"weakcallableproxy\"") },
});

fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(?*anyopaque, null)"); return; }
    try self.emit("@as(?*anyopaque, @ptrCast(&"); try self.genExpr(args[0]); try self.emit("))");
}

fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(?*anyopaque, null)"); return; }
    try self.genExpr(args[0]);
}

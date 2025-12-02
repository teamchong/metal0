/// Python weakref module - Weak references
const std = @import("std");
const h = @import("mod_helper.zig");

const genRef = h.wrap("@as(?*anyopaque, @ptrCast(&", "))", "@as(?*anyopaque, null)");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ref", genRef }, .{ "proxy", h.pass("@as(?*anyopaque, null)") },
    .{ "getweakrefcount", h.I64(0) }, .{ "getweakrefs", h.c("&[_]*anyopaque{}") },
    .{ "WeakSet", h.c("struct { items: std.ArrayList(*anyopaque) = .{}, pub fn add(__self: *@This(), item: anytype) void { __self.items.append(__global_allocator, @ptrCast(&item)) catch {}; } pub fn discard(__self: *@This(), item: anytype) void { _ = item; } pub fn __len__(__self: *@This()) usize { return __self.items.items.len; } pub fn __contains__(__self: *@This(), item: anytype) bool { _ = item; return false; } }{}") },
    .{ "WeakKeyDictionary", h.c("struct { data: hashmap_helper.StringHashMap([]const u8) = .{}, pub fn get(__self: *@This(), key: anytype) ?[]const u8 { _ = key; return null; } pub fn put(__self: *@This(), key: anytype, value: anytype) void { _ = key; _ = value; } pub fn __len__(__self: *@This()) usize { return __self.data.count(); } }{}") },
    .{ "WeakValueDictionary", h.c("struct { data: hashmap_helper.StringHashMap(*anyopaque) = .{}, pub fn get(__self: *@This(), key: []const u8) ?*anyopaque { return __self.data.get(key); } pub fn put(__self: *@This(), key: []const u8, value: anytype) void { __self.data.put(key, @ptrCast(&value)) catch {}; } pub fn __len__(__self: *@This()) usize { return __self.data.count(); } }{}") },
    .{ "WeakMethod", genRef },
    .{ "finalize", h.c("struct { alive: bool = true, pub fn __call__(__self: *@This()) void { __self.alive = false; } pub fn detach(__self: *@This()) ?@This() { if (__self.alive) { __self.alive = false; return __self.*; } return null; } pub fn peek(__self: *@This()) ?@This() { if (__self.alive) return __self.*; return null; } pub fn atexit(__self: *@This()) bool { return __self.alive; } }{}") },
    .{ "ReferenceType", h.c("\"weakref\"") }, .{ "ProxyType", h.c("\"weakproxy\"") },
    .{ "CallableProxyType", h.c("\"weakcallableproxy\"") },
});

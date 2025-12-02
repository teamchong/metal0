/// Python _weakref module - Weak reference support (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ref", genRef }, .{ "proxy", genProxy }, .{ "getweakrefcount", h.I64(0) },
    .{ "getweakrefs", h.c("&[_]@TypeOf(.{}){}") }, .{ "CallableProxyType", h.c("@TypeOf(.{})") },
    .{ "ProxyType", h.c("@TypeOf(.{})") }, .{ "ReferenceType", h.c("@TypeOf(.{})") },
});

fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .ptr = @intFromPtr(&obj) }; }"); } else { try self.emit(".{ .ptr = 0 }"); }
}

fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("null");
}

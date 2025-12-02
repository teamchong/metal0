/// Python _weakref module - Weak reference support (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ref", genRef }, .{ "proxy", genProxy }, .{ "getweakrefcount", genI64_0 }, .{ "getweakrefs", genTypeArr }, .{ "CallableProxyType", genType }, .{ "ProxyType", genType }, .{ "ReferenceType", genType },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@TypeOf(.{})"); }
fn genTypeArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }

fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .ptr = @intFromPtr(&obj) }; }"); } else { try self.emit(".{ .ptr = 0 }"); }
}

fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("null");
}

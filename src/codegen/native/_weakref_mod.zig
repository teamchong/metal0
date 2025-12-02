/// Python _weakref module - Weak reference support (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ref", genRef }, .{ "proxy", genProxy }, .{ "getweakrefcount", genConst("@as(i64, 0)") },
    .{ "getweakrefs", genConst("&[_]@TypeOf(.{}){}") }, .{ "CallableProxyType", genConst("@TypeOf(.{})") },
    .{ "ProxyType", genConst("@TypeOf(.{})") }, .{ "ReferenceType", genConst("@TypeOf(.{})") },
});

fn genRef(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const obj = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .ptr = @intFromPtr(&obj) }; }"); } else { try self.emit(".{ .ptr = 0 }"); }
}

fn genProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("null");
}

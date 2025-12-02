/// Python _weakrefset module - Internal WeakSet support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genWeakSetData(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = .{} }"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 0)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "WeakSet", genWeakSetData }, .{ "add", genUnit }, .{ "discard", genUnit }, .{ "remove", genUnit },
    .{ "pop", genNull }, .{ "clear", genUnit }, .{ "copy", genWeakSetData }, .{ "update", genUnit },
    .{ "__len__", genZero }, .{ "__contains__", genFalse }, .{ "issubset", genTrue }, .{ "issuperset", genTrue },
    .{ "union", genWeakSetData }, .{ "intersection", genWeakSetData }, .{ "difference", genWeakSetData },
    .{ "symmetric_difference", genWeakSetData },
});

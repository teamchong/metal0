/// Python pty module - Pseudo-terminal utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fork", genPair }, .{ "openpty", genPair }, .{ "spawn", genI32_0 },
    .{ "STDIN_FILENO", genI32_0 }, .{ "STDOUT_FILENO", genI32_1 }, .{ "STDERR_FILENO", genI32_2 }, .{ "CHILD", genI32_0 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genPair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, -1), @as(i32, -1) }"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }

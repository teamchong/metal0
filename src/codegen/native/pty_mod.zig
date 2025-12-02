/// Python pty module - Pseudo-terminal utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fork", genConst(".{ @as(i32, -1), @as(i32, -1) }") }, .{ "openpty", genConst(".{ @as(i32, -1), @as(i32, -1) }") },
    .{ "spawn", genConst("@as(i32, 0)") },
    .{ "STDIN_FILENO", genConst("@as(i32, 0)") }, .{ "STDOUT_FILENO", genConst("@as(i32, 1)") },
    .{ "STDERR_FILENO", genConst("@as(i32, 2)") }, .{ "CHILD", genConst("@as(i32, 0)") },
});

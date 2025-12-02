/// Python _weakrefset module - Internal WeakSet support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "WeakSet", genConst(".{ .data = .{} }") }, .{ "add", genConst("{}") }, .{ "discard", genConst("{}") }, .{ "remove", genConst("{}") },
    .{ "pop", genConst("null") }, .{ "clear", genConst("{}") }, .{ "copy", genConst(".{ .data = .{} }") }, .{ "update", genConst("{}") },
    .{ "__len__", genConst("@as(usize, 0)") }, .{ "__contains__", genConst("false") }, .{ "issubset", genConst("true") }, .{ "issuperset", genConst("true") },
    .{ "union", genConst(".{ .data = .{} }") }, .{ "intersection", genConst(".{ .data = .{} }") }, .{ "difference", genConst(".{ .data = .{} }") },
    .{ "symmetric_difference", genConst(".{ .data = .{} }") },
});

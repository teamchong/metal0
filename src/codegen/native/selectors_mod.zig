/// Python selectors module - High-level I/O multiplexing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "DefaultSelector", genConst(".{}") }, .{ "SelectSelector", genConst(".{}") }, .{ "PollSelector", genConst(".{}") },
    .{ "EpollSelector", genConst(".{}") }, .{ "KqueueSelector", genConst(".{}") }, .{ "DevpollSelector", genConst(".{}") },
    .{ "EVENT_READ", genConst("@as(i32, 1)") }, .{ "EVENT_WRITE", genConst("@as(i32, 2)") },
});

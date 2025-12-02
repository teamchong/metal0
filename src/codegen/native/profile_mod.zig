/// Python profile/cProfile module - Performance profiling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Profile", genConst(".{ .stats = @as(?*anyopaque, null) }") },
    .{ "run", genConst("{}") }, .{ "runctx", genConst("{}") },
});

pub const genCProfile = genConst(".{ .stats = @as(?*anyopaque, null) }");

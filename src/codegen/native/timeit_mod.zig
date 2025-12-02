/// Python timeit module - Measure execution time
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "timeit", genConst("@as(f64, 0.0)") },
    .{ "repeat", genConst("&[_]f64{}") },
    .{ "default_timer", genConst("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0") },
    .{ "Timer", genConst(".{ .stmt = \"pass\", .setup = \"pass\", .timer = @as(?*const fn () f64, null), .globals = @as(?*anyopaque, null) }") },
});

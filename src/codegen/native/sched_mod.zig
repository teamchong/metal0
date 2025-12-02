/// Python sched module - Event scheduler
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "scheduler", genConst(".{ .queue = &[_]@TypeOf(.{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }){} }") },
    .{ "Event", genConst(".{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }") },
});

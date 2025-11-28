/// Python sched module - Event scheduler
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sched.scheduler(timefunc=time.monotonic, delayfunc=time.sleep)
pub fn genScheduler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .queue = &[_]@TypeOf(.{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }){} }");
}

/// Generate sched.Event namedtuple
pub fn genEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }");
}

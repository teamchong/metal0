/// Python sched module - Event scheduler
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "scheduler", genScheduler },
    .{ "Event", genEvent },
});

fn genScheduler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .queue = &[_]@TypeOf(.{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }){} }"), builder_mod.EmitConfig.forExpression());
}

fn genEvent(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }"), builder_mod.EmitConfig.forExpression());
}

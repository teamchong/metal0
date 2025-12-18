/// Python timeit module - Measure execution time
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "timeit", genTimeit },
    .{ "repeat", genRepeat },
    .{ "default_timer", genDefaultTimer },
    .{ "Timer", genTimer },
});

fn genTimeit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.float(0.0), builder_mod.EmitConfig.forExpression());
}

fn genRepeat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]f64{}"), builder_mod.EmitConfig.forExpression());
}

fn genDefaultTimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0"), builder_mod.EmitConfig.forExpression());
}

fn genTimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .stmt = \"pass\", .setup = \"pass\", .timer = @as(?*const fn () f64, null), .globals = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

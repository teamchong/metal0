/// Python tracemalloc module - Trace memory allocations
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start", genStart },
    .{ "stop", genStop },
    .{ "is_tracing", genIsTracing },
    .{ "clear_traces", genClearTraces },
    .{ "get_object_traceback", genGetObjectTraceback },
    .{ "get_traceback_limit", genGetTracebackLimit },
    .{ "get_traced_memory", genGetTracedMemory },
    .{ "reset_peak", genResetPeak },
    .{ "get_tracemalloc_memory", genGetTracemallocMemory },
    .{ "take_snapshot", genTakeSnapshot },
    .{ "Snapshot", genSnapshot },
    .{ "Statistic", genStatistic },
    .{ "StatisticDiff", genStatisticDiff },
    .{ "Trace", genTrace },
    .{ "Traceback", genTraceback },
    .{ "Frame", genFrame },
    .{ "Filter", genFilter },
    .{ "DomainFilter", genDomainFilter },
});

fn genStart(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genStop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genIsTracing(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genClearTraces(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetObjectTraceback(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genGetTracebackLimit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genGetTracedMemory(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i64, 0), @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genResetPeak(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetTracemallocMemory(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genTakeSnapshot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .traces = &[_]@TypeOf(.{}){} }"), builder_mod.EmitConfig.forExpression());
}

fn genSnapshot(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .traces = &[_]@TypeOf(.{}){} }"), builder_mod.EmitConfig.forExpression());
}

fn genStatistic(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .traceback = null, .size = 0, .count = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genStatisticDiff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .traceback = null, .size = 0, .size_diff = 0, .count = 0, .count_diff = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genTrace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .traceback = null, .size = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genTraceback(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .frames = &[_]@TypeOf(.{}){} }"), builder_mod.EmitConfig.forExpression());
}

fn genFrame(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .filename = \"\", .lineno = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genFilter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .inclusive = true, .filename_pattern = \"*\", .lineno = null, .all_frames = false, .domain = null }"), builder_mod.EmitConfig.forExpression());
}

fn genDomainFilter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .inclusive = true, .domain = 0 }"), builder_mod.EmitConfig.forExpression());
}

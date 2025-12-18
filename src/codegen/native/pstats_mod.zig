/// Python pstats module - Statistics object for the profiler
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Stats", genStats },
    .{ "SortKey", genSortKey },
    .{ "strip_dirs", genStripDirs },
    .{ "add", genAdd },
    .{ "dump_stats", genDumpStats },
    .{ "sort_stats", genSortStats },
    .{ "reverse_order", genReverseOrder },
    .{ "print_stats", genPrintStats },
    .{ "print_callers", genPrintCallers },
    .{ "print_callees", genPrintCallees },
    .{ "get_stats_profile", genGetStatsProfile },
    .{ "FunctionProfile", genFunctionProfile },
    .{ "StatsProfile", genStatsProfile },
});

fn genStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .stats = .{}, .total_calls = 0, .prim_calls = 0, .total_tt = 0.0, .stream = null }"), builder_mod.EmitConfig.forExpression());
}

fn genSortKey(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .CALLS = 0, .CUMULATIVE = 1, .FILENAME = 2, .LINE = 3, .NAME = 4, .NFL = 5, .PCALLS = 6, .STDNAME = 7, .TIME = 8 }"), builder_mod.EmitConfig.forExpression());
}

fn genStripDirs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genAdd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genDumpStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSortStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genReverseOrder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintStats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintCallers(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintCallees(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetStatsProfile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .total_tt = 0.0, .func_profiles = .{} }"), builder_mod.EmitConfig.forExpression());
}

fn genFunctionProfile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .ncalls = 0, .tottime = 0.0, .percall_tottime = 0.0, .cumtime = 0.0, .percall_cumtime = 0.0, .file_name = \"\", .line_number = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genStatsProfile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .total_tt = 0.0, .func_profiles = .{} }"), builder_mod.EmitConfig.forExpression());
}

/// Python _lsprof module - Internal profiler support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "profiler", genProfiler },
    .{ "enable", genEnable },
    .{ "disable", genDisable },
    .{ "clear", genClear },
    .{ "getstats", genGetstats },
    .{ "profiler_entry", genProfilerEntry },
    .{ "profiler_subentry", genProfilerSubentry },
});

fn genProfiler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .timer = null, .timeunit = 0.0, .subcalls = true, .builtins = true }"), builder_mod.EmitConfig.forExpression());
}

fn genEnable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDisable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genClear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetstats(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genProfilerEntry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0, .calls = null }"), builder_mod.EmitConfig.forExpression());
}

fn genProfilerSubentry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0 }"), builder_mod.EmitConfig.forExpression());
}


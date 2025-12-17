/// Python colorsys module - Color system conversions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "rgb_to_yiq", genRgbToYiq },
    .{ "yiq_to_rgb", genYiqToRgb },
    .{ "rgb_to_hls", genRgbToHls },
    .{ "hls_to_rgb", genHlsToRgb },
    .{ "rgb_to_hsv", genRgbToHsv },
    .{ "hsv_to_rgb", genHsvToRgb },
});

fn genRgbToYiq(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genYiqToRgb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genRgbToHls(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genHlsToRgb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genRgbToHsv(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}

fn genHsvToRgb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }"), builder_mod.EmitConfig.forExpression());
}


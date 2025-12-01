/// Python colorsys module - Color system conversions
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "rgb_to_yiq", genRgb_to_yiq },
    .{ "yiq_to_rgb", genYiq_to_rgb },
    .{ "rgb_to_hls", genRgb_to_hls },
    .{ "hls_to_rgb", genHls_to_rgb },
    .{ "rgb_to_hsv", genRgb_to_hsv },
    .{ "hsv_to_rgb", genHsv_to_rgb },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate colorsys.rgb_to_yiq(r, g, b)
pub fn genRgb_to_yiq(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate colorsys.yiq_to_rgb(y, i, q)
pub fn genYiq_to_rgb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate colorsys.rgb_to_hls(r, g, b)
pub fn genRgb_to_hls(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate colorsys.hls_to_rgb(h, l, s)
pub fn genHls_to_rgb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate colorsys.rgb_to_hsv(r, g, b)
pub fn genRgb_to_hsv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate colorsys.hsv_to_rgb(h, s, v)
pub fn genHsv_to_rgb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

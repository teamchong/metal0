/// Python colorsys module - Color system conversions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "rgb_to_yiq", genColorTuple },
    .{ "yiq_to_rgb", genColorTuple },
    .{ "rgb_to_hls", genColorTuple },
    .{ "hls_to_rgb", genColorTuple },
    .{ "rgb_to_hsv", genColorTuple },
    .{ "hsv_to_rgb", genColorTuple },
});

/// All color conversions return (0.0, 0.0, 0.0) placeholder
fn genColorTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0), @as(f64, 0.0) }");
}

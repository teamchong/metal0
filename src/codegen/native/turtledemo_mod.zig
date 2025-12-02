/// Python turtledemo module - Turtle graphics demos
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "main", genUnit }, .{ "bytedesign", genUnit }, .{ "chaos", genUnit }, .{ "clock", genUnit },
    .{ "colormixer", genUnit }, .{ "forest", genUnit }, .{ "fractalcurves", genUnit }, .{ "lindenmayer", genUnit },
    .{ "minimal_hanoi", genUnit }, .{ "nim", genUnit }, .{ "paint", genUnit }, .{ "peace", genUnit },
    .{ "penrose", genUnit }, .{ "planet_and_moon", genUnit }, .{ "rosette", genUnit }, .{ "round_dance", genUnit },
    .{ "sorting_animate", genUnit }, .{ "tree", genUnit }, .{ "two_canvases", genUnit }, .{ "yinyang", genUnit },
});

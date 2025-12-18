/// Python turtledemo module - Turtle graphics demos
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "main", genVoid },
    .{ "bytedesign", genVoid },
    .{ "chaos", genVoid },
    .{ "clock", genVoid },
    .{ "colormixer", genVoid },
    .{ "forest", genVoid },
    .{ "fractalcurves", genVoid },
    .{ "lindenmayer", genVoid },
    .{ "minimal_hanoi", genVoid },
    .{ "nim", genVoid },
    .{ "paint", genVoid },
    .{ "peace", genVoid },
    .{ "penrose", genVoid },
    .{ "planet_and_moon", genVoid },
    .{ "rosette", genVoid },
    .{ "round_dance", genVoid },
    .{ "sorting_animate", genVoid },
    .{ "tree", genVoid },
    .{ "two_canvases", genVoid },
    .{ "yinyang", genVoid },
});

fn genVoid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

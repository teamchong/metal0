/// Python turtle module - Turtle graphics
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "turtle", genTurtle },
    .{ "screen", genScreen },
    .{ "forward", genVoid },
    .{ "fd", genVoid },
    .{ "backward", genVoid },
    .{ "bk", genVoid },
    .{ "right", genVoid },
    .{ "rt", genVoid },
    .{ "left", genVoid },
    .{ "lt", genVoid },
    .{ "goto", genVoid },
    .{ "setpos", genVoid },
    .{ "setposition", genVoid },
    .{ "setx", genVoid },
    .{ "sety", genVoid },
    .{ "setheading", genVoid },
    .{ "seth", genVoid },
    .{ "home", genVoid },
    .{ "circle", genVoid },
    .{ "dot", genVoid },
    .{ "stamp", genStamp },
    .{ "clearstamp", genVoid },
    .{ "clearstamps", genVoid },
    .{ "undo", genVoid },
    .{ "speed", genVoid },
    .{ "position", genPosition },
    .{ "pos", genPosition },
    .{ "xcor", genZeroFloat },
    .{ "ycor", genZeroFloat },
    .{ "heading", genZeroFloat },
    .{ "distance", genZeroFloat },
    .{ "pendown", genVoid },
    .{ "pd", genVoid },
    .{ "down", genVoid },
    .{ "penup", genVoid },
    .{ "pu", genVoid },
    .{ "up", genVoid },
    .{ "pensize", genVoid },
    .{ "width", genVoid },
    .{ "pencolor", genVoid },
    .{ "fillcolor", genVoid },
    .{ "color", genVoid },
    .{ "filling", genFilling },
    .{ "begin_fill", genVoid },
    .{ "end_fill", genVoid },
    .{ "reset", genVoid },
    .{ "clear", genVoid },
    .{ "write", genVoid },
    .{ "showturtle", genVoid },
    .{ "st", genVoid },
    .{ "hideturtle", genVoid },
    .{ "ht", genVoid },
    .{ "isvisible", genTrue },
    .{ "shape", genVoid },
    .{ "shapesize", genVoid },
    .{ "turtlesize", genVoid },
    .{ "bgcolor", genVoid },
    .{ "bgpic", genVoid },
    .{ "done", genVoid },
    .{ "mainloop", genVoid },
    .{ "exitonclick", genVoid },
    .{ "bye", genVoid },
    .{ "tracer", genVoid },
    .{ "update", genVoid },
    .{ "delay", genVoid },
    .{ "mode", genVoid },
    .{ "colormode", genVoid },
    .{ "getcanvas", genEmptyStruct },
    .{ "getshapes", genGetshapes },
    .{ "register_shape", genVoid },
    .{ "addshape", genVoid },
    .{ "turtles", genTurtles },
    .{ "window_height", genWindowSize },
    .{ "window_width", genWindowSize },
    .{ "setup", genVoid },
    .{ "title", genVoid },
});

fn genTurtle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genScreen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genVoid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genStamp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("0"), builder_mod.EmitConfig.forExpression());
}

fn genPosition(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ 0.0, 0.0 }"), builder_mod.EmitConfig.forExpression());
}

fn genZeroFloat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.float(0.0), builder_mod.EmitConfig.forExpression());
}

fn genFilling(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("false"), builder_mod.EmitConfig.forExpression());
}

fn genTrue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("true"), builder_mod.EmitConfig.forExpression());
}

fn genEmptyStruct(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetshapes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"arrow\", \"turtle\", \"circle\", \"square\", \"triangle\", \"classic\" }"), builder_mod.EmitConfig.forExpression());
}

fn genTurtles(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genWindowSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("400"), builder_mod.EmitConfig.forExpression());
}

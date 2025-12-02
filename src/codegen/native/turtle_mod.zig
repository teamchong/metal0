/// Python turtle module - Turtle graphics
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "turtle", genEmpty }, .{ "screen", genEmpty }, .{ "forward", genUnit }, .{ "fd", genUnit },
    .{ "backward", genUnit }, .{ "bk", genUnit }, .{ "right", genUnit }, .{ "rt", genUnit },
    .{ "left", genUnit }, .{ "lt", genUnit }, .{ "goto", genUnit }, .{ "setpos", genUnit },
    .{ "setposition", genUnit }, .{ "setx", genUnit }, .{ "sety", genUnit }, .{ "setheading", genUnit },
    .{ "seth", genUnit }, .{ "home", genUnit }, .{ "circle", genUnit }, .{ "dot", genUnit },
    .{ "stamp", genZero }, .{ "clearstamp", genUnit }, .{ "clearstamps", genUnit }, .{ "undo", genUnit },
    .{ "speed", genUnit }, .{ "position", genPos }, .{ "pos", genPos }, .{ "xcor", genF64_0 },
    .{ "ycor", genF64_0 }, .{ "heading", genF64_0 }, .{ "distance", genF64_0 }, .{ "pendown", genUnit },
    .{ "pd", genUnit }, .{ "down", genUnit }, .{ "penup", genUnit }, .{ "pu", genUnit },
    .{ "up", genUnit }, .{ "pensize", genUnit }, .{ "width", genUnit }, .{ "pencolor", genUnit },
    .{ "fillcolor", genUnit }, .{ "color", genUnit }, .{ "filling", genFalse }, .{ "begin_fill", genUnit },
    .{ "end_fill", genUnit }, .{ "reset", genUnit }, .{ "clear", genUnit }, .{ "write", genUnit },
    .{ "showturtle", genUnit }, .{ "st", genUnit }, .{ "hideturtle", genUnit }, .{ "ht", genUnit },
    .{ "isvisible", genTrue }, .{ "shape", genUnit }, .{ "shapesize", genUnit }, .{ "turtlesize", genUnit },
    .{ "bgcolor", genUnit }, .{ "bgpic", genUnit }, .{ "done", genUnit }, .{ "mainloop", genUnit },
    .{ "exitonclick", genUnit }, .{ "bye", genUnit }, .{ "tracer", genUnit }, .{ "update", genUnit },
    .{ "delay", genUnit }, .{ "mode", genUnit }, .{ "colormode", genUnit }, .{ "getcanvas", genEmpty },
    .{ "getshapes", genShapes }, .{ "register_shape", genUnit }, .{ "addshape", genUnit },
    .{ "turtles", genTurtles }, .{ "window_height", gen400 }, .{ "window_width", gen400 },
    .{ "setup", genUnit }, .{ "title", genUnit },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn gen400(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "400"); }
fn genF64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0.0"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genPos(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ 0.0, 0.0 }"); }
fn genShapes(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"arrow\", \"turtle\", \"circle\", \"square\", \"triangle\", \"classic\" }"); }
fn genTurtles(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }

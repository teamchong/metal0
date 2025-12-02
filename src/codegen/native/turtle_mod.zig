/// Python turtle module - Turtle graphics
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "turtle", genConst(".{}") }, .{ "screen", genConst(".{}") },
    .{ "forward", genConst("{}") }, .{ "fd", genConst("{}") }, .{ "backward", genConst("{}") }, .{ "bk", genConst("{}") },
    .{ "right", genConst("{}") }, .{ "rt", genConst("{}") }, .{ "left", genConst("{}") }, .{ "lt", genConst("{}") },
    .{ "goto", genConst("{}") }, .{ "setpos", genConst("{}") }, .{ "setposition", genConst("{}") },
    .{ "setx", genConst("{}") }, .{ "sety", genConst("{}") }, .{ "setheading", genConst("{}") }, .{ "seth", genConst("{}") },
    .{ "home", genConst("{}") }, .{ "circle", genConst("{}") }, .{ "dot", genConst("{}") },
    .{ "stamp", genConst("0") }, .{ "clearstamp", genConst("{}") }, .{ "clearstamps", genConst("{}") }, .{ "undo", genConst("{}") },
    .{ "speed", genConst("{}") }, .{ "position", genConst(".{ 0.0, 0.0 }") }, .{ "pos", genConst(".{ 0.0, 0.0 }") },
    .{ "xcor", genConst("0.0") }, .{ "ycor", genConst("0.0") }, .{ "heading", genConst("0.0") }, .{ "distance", genConst("0.0") },
    .{ "pendown", genConst("{}") }, .{ "pd", genConst("{}") }, .{ "down", genConst("{}") },
    .{ "penup", genConst("{}") }, .{ "pu", genConst("{}") }, .{ "up", genConst("{}") },
    .{ "pensize", genConst("{}") }, .{ "width", genConst("{}") }, .{ "pencolor", genConst("{}") },
    .{ "fillcolor", genConst("{}") }, .{ "color", genConst("{}") }, .{ "filling", genConst("false") },
    .{ "begin_fill", genConst("{}") }, .{ "end_fill", genConst("{}") }, .{ "reset", genConst("{}") },
    .{ "clear", genConst("{}") }, .{ "write", genConst("{}") },
    .{ "showturtle", genConst("{}") }, .{ "st", genConst("{}") }, .{ "hideturtle", genConst("{}") }, .{ "ht", genConst("{}") },
    .{ "isvisible", genConst("true") }, .{ "shape", genConst("{}") }, .{ "shapesize", genConst("{}") }, .{ "turtlesize", genConst("{}") },
    .{ "bgcolor", genConst("{}") }, .{ "bgpic", genConst("{}") }, .{ "done", genConst("{}") }, .{ "mainloop", genConst("{}") },
    .{ "exitonclick", genConst("{}") }, .{ "bye", genConst("{}") }, .{ "tracer", genConst("{}") }, .{ "update", genConst("{}") },
    .{ "delay", genConst("{}") }, .{ "mode", genConst("{}") }, .{ "colormode", genConst("{}") }, .{ "getcanvas", genConst(".{}") },
    .{ "getshapes", genConst("&[_][]const u8{ \"arrow\", \"turtle\", \"circle\", \"square\", \"triangle\", \"classic\" }") },
    .{ "register_shape", genConst("{}") }, .{ "addshape", genConst("{}") },
    .{ "turtles", genConst("&[_]@TypeOf(.{}){}") }, .{ "window_height", genConst("400") }, .{ "window_width", genConst("400") },
    .{ "setup", genConst("{}") }, .{ "title", genConst("{}") },
});

/// Python turtle module - Turtle graphics
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "turtle", h.c(".{}") }, .{ "screen", h.c(".{}") },
    .{ "forward", h.c("{}") }, .{ "fd", h.c("{}") }, .{ "backward", h.c("{}") }, .{ "bk", h.c("{}") },
    .{ "right", h.c("{}") }, .{ "rt", h.c("{}") }, .{ "left", h.c("{}") }, .{ "lt", h.c("{}") },
    .{ "goto", h.c("{}") }, .{ "setpos", h.c("{}") }, .{ "setposition", h.c("{}") },
    .{ "setx", h.c("{}") }, .{ "sety", h.c("{}") }, .{ "setheading", h.c("{}") }, .{ "seth", h.c("{}") },
    .{ "home", h.c("{}") }, .{ "circle", h.c("{}") }, .{ "dot", h.c("{}") },
    .{ "stamp", h.c("0") }, .{ "clearstamp", h.c("{}") }, .{ "clearstamps", h.c("{}") }, .{ "undo", h.c("{}") },
    .{ "speed", h.c("{}") }, .{ "position", h.c(".{ 0.0, 0.0 }") }, .{ "pos", h.c(".{ 0.0, 0.0 }") },
    .{ "xcor", h.F64(0.0) }, .{ "ycor", h.F64(0.0) }, .{ "heading", h.F64(0.0) }, .{ "distance", h.F64(0.0) },
    .{ "pendown", h.c("{}") }, .{ "pd", h.c("{}") }, .{ "down", h.c("{}") },
    .{ "penup", h.c("{}") }, .{ "pu", h.c("{}") }, .{ "up", h.c("{}") },
    .{ "pensize", h.c("{}") }, .{ "width", h.c("{}") }, .{ "pencolor", h.c("{}") },
    .{ "fillcolor", h.c("{}") }, .{ "color", h.c("{}") }, .{ "filling", h.c("false") },
    .{ "begin_fill", h.c("{}") }, .{ "end_fill", h.c("{}") }, .{ "reset", h.c("{}") },
    .{ "clear", h.c("{}") }, .{ "write", h.c("{}") },
    .{ "showturtle", h.c("{}") }, .{ "st", h.c("{}") }, .{ "hideturtle", h.c("{}") }, .{ "ht", h.c("{}") },
    .{ "isvisible", h.c("true") }, .{ "shape", h.c("{}") }, .{ "shapesize", h.c("{}") }, .{ "turtlesize", h.c("{}") },
    .{ "bgcolor", h.c("{}") }, .{ "bgpic", h.c("{}") }, .{ "done", h.c("{}") }, .{ "mainloop", h.c("{}") },
    .{ "exitonclick", h.c("{}") }, .{ "bye", h.c("{}") }, .{ "tracer", h.c("{}") }, .{ "update", h.c("{}") },
    .{ "delay", h.c("{}") }, .{ "mode", h.c("{}") }, .{ "colormode", h.c("{}") }, .{ "getcanvas", h.c(".{}") },
    .{ "getshapes", h.c("&[_][]const u8{ \"arrow\", \"turtle\", \"circle\", \"square\", \"triangle\", \"classic\" }") },
    .{ "register_shape", h.c("{}") }, .{ "addshape", h.c("{}") },
    .{ "turtles", h.c("&[_]@TypeOf(.{}){}") }, .{ "window_height", h.c("400") }, .{ "window_width", h.c("400") },
    .{ "setup", h.c("{}") }, .{ "title", h.c("{}") },
});

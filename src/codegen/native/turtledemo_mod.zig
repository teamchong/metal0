/// Python turtledemo module - Turtle graphics demos
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "main", h.c("{}") }, .{ "bytedesign", h.c("{}") }, .{ "chaos", h.c("{}") }, .{ "clock", h.c("{}") },
    .{ "colormixer", h.c("{}") }, .{ "forest", h.c("{}") }, .{ "fractalcurves", h.c("{}") }, .{ "lindenmayer", h.c("{}") },
    .{ "minimal_hanoi", h.c("{}") }, .{ "nim", h.c("{}") }, .{ "paint", h.c("{}") }, .{ "peace", h.c("{}") },
    .{ "penrose", h.c("{}") }, .{ "planet_and_moon", h.c("{}") }, .{ "rosette", h.c("{}") }, .{ "round_dance", h.c("{}") },
    .{ "sorting_animate", h.c("{}") }, .{ "tree", h.c("{}") }, .{ "two_canvases", h.c("{}") }, .{ "yinyang", h.c("{}") },
});

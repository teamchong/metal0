/// Python _weakrefset module - Internal WeakSet support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "WeakSet", h.c(".{ .data = .{} }") }, .{ "add", h.c("{}") }, .{ "discard", h.c("{}") }, .{ "remove", h.c("{}") },
    .{ "pop", h.c("null") }, .{ "clear", h.c("{}") }, .{ "copy", h.c(".{ .data = .{} }") }, .{ "update", h.c("{}") },
    .{ "__len__", h.c("@as(usize, 0)") }, .{ "__contains__", h.c("false") }, .{ "issubset", h.c("true") }, .{ "issuperset", h.c("true") },
    .{ "union", h.c(".{ .data = .{} }") }, .{ "intersection", h.c(".{ .data = .{} }") }, .{ "difference", h.c(".{ .data = .{} }") },
    .{ "symmetric_difference", h.c(".{ .data = .{} }") },
});

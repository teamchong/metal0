/// Python _queue module - Internal queue support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "simple_queue", h.c(".{ .items = &[_]@TypeOf(null){} }") }, .{ "put", h.c("{}") }, .{ "put_nowait", h.c("{}") },
    .{ "get", h.c("null") }, .{ "get_nowait", h.c("null") }, .{ "empty", h.c("true") }, .{ "qsize", h.c("@as(i64, 0)") },
});

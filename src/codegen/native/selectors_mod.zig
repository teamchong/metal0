/// Python selectors module - High-level I/O multiplexing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "DefaultSelector", h.c(".{}") }, .{ "SelectSelector", h.c(".{}") }, .{ "PollSelector", h.c(".{}") },
    .{ "EpollSelector", h.c(".{}") }, .{ "KqueueSelector", h.c(".{}") }, .{ "DevpollSelector", h.c(".{}") },
    .{ "EVENT_READ", h.I32(1) }, .{ "EVENT_WRITE", h.I32(2) },
});

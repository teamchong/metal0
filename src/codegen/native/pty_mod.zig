/// Python pty module - Pseudo-terminal utilities
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fork", h.c(".{ @as(i32, -1), @as(i32, -1) }") }, .{ "openpty", h.c(".{ @as(i32, -1), @as(i32, -1) }") },
    .{ "spawn", h.I32(0) },
    .{ "STDIN_FILENO", h.I32(0) }, .{ "STDOUT_FILENO", h.I32(1) },
    .{ "STDERR_FILENO", h.I32(2) }, .{ "CHILD", h.I32(0) },
});

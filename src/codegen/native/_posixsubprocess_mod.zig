/// Python _posixsubprocess module - Internal posixsubprocess support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fork_exec", h.I32(-1) },
    .{ "cloexec_pipe", h.c(".{ @as(i32, -1), @as(i32, -1) }") },
});

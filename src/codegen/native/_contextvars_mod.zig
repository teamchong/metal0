/// Python _contextvars module - Internal contextvars support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "context_var", h.wrap("blk: { const name = ", "; break :blk .{ .name = name, .default = null }; }", ".{ .name = \"\", .default = null }") }, .{ "context", h.c(".{}") }, .{ "token", h.c(".{ .var = null, .old_value = null, .used = false }") },
    .{ "copy_context", h.c(".{}") }, .{ "get", h.c("null") }, .{ "set", h.c(".{ .var = null, .old_value = null, .used = false }") },
    .{ "reset", h.c("{}") }, .{ "run", h.c("null") }, .{ "copy", h.c(".{}") },
});

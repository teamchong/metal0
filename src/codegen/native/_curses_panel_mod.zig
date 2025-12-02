/// Python _curses_panel module - Internal curses panel support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new_panel", h.c(".{ .window = null }") }, .{ "bottom_panel", h.c("null") }, .{ "top_panel", h.c("null") }, .{ "update_panels", h.c("{}") },
    .{ "above", h.c("null") }, .{ "below", h.c("null") }, .{ "bottom", h.c("{}") }, .{ "hidden", h.c("false") },
    .{ "hide", h.c("{}") }, .{ "move", h.c("{}") }, .{ "replace", h.c("{}") }, .{ "set_userptr", h.c("{}") },
    .{ "show", h.c("{}") }, .{ "top", h.c("{}") }, .{ "userptr", h.c("null") }, .{ "window", h.c("null") },
    .{ "error", h.err("PanelError") },
});

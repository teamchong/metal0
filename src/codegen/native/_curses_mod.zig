/// Python _curses module - Internal curses support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "initscr", h.c(".{ .lines = 24, .cols = 80 }") }, .{ "endwin", h.c("{}") }, .{ "newwin", h.c(".{ .lines = 24, .cols = 80, .y = 0, .x = 0 }") }, .{ "newpad", h.c(".{ .lines = 24, .cols = 80 }") },
    .{ "start_color", h.c("{}") }, .{ "init_pair", h.c("{}") }, .{ "color_pair", h.I32(0) },
    .{ "cbreak", h.c("{}") }, .{ "nocbreak", h.c("{}") }, .{ "echo", h.c("{}") }, .{ "noecho", h.c("{}") },
    .{ "raw", h.c("{}") }, .{ "noraw", h.c("{}") }, .{ "curs_set", h.I32(1) },
    .{ "has_colors", h.c("true") }, .{ "can_change_color", h.c("true") },
    .{ "COLORS", h.I32(256) }, .{ "COLOR_PAIRS", h.I32(256) }, .{ "LINES", h.I32(24) }, .{ "COLS", h.I32(80) },
    .{ "error", h.err("CursesError") },
});

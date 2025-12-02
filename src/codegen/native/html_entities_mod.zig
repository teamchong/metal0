/// Python html.entities module - HTML entity definitions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "html5", h.c(".{}") },
    .{ "name2codepoint", h.c(".{}") },
    .{ "codepoint2name", h.c(".{}") },
    .{ "entitydefs", h.c(".{}") },
});

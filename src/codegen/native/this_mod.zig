/// Python this module - The Zen of Python easter egg
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "s", h.c("\"Gur Mra bs Clguba, ol Gvz Crgref...\"") },
    .{ "d", h.c(".{}") },
});

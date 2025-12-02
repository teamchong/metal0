/// Python pydoc_data module - Pydoc data files
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "topics", h.c(".{}") },
});

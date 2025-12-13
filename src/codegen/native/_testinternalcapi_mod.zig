const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_configs", h.c(".{}") },
    .{ "get_recursion_depth", h.c("@as(i64, 1000)") },
});

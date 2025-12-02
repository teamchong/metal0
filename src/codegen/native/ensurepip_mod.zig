/// Python ensurepip module - Bootstrap pip installer
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "version", h.c("\"24.0\"") },
    .{ "bootstrap", h.c("{}") },
    .{ "_main", h.I32(0) },
});

/// Python zipapp module - Manage executable Python zip archives
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "create_archive", h.discard("{}") }, .{ "get_interpreter", h.discard("null") },
});

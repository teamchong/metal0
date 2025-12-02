/// Python _frozen_importlib module - Frozen import machinery
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "module_spec", h.wrap("blk: { const name = ", "; break :blk .{ .name = name, .loader = null, .origin = null, .submodule_search_locations = null }; }", ".{ .name = \"\", .loader = null, .origin = null, .submodule_search_locations = null }") }, .{ "builtin_importer", h.c(".{}") }, .{ "frozen_importer", h.c(".{}") },
    .{ "init_module_attrs", h.c("{}") }, .{ "call_with_frames_removed", h.c("null") }, .{ "find_and_load", h.c("null") },
    .{ "find_and_load_unlocked", h.c("null") }, .{ "gcd_import", h.c("null") }, .{ "handle_fromlist", h.c("null") },
    .{ "lock_unlock_module", h.c(".{}") }, .{ "import", h.c("null") },
});

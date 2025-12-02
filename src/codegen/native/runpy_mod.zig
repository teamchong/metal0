/// Python runpy module - Run Python modules (AOT-limited, dynamic execution stubs)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "run_module", h.c(".{}") }, .{ "run_path", h.c(".{}") },
});

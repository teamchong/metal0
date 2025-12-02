/// Python tomllib module - Parse TOML files (Python 3.11+)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "load", h.discard(".{}") }, .{ "loads", h.discard(".{}") }, .{ "TOMLDecodeError", h.err("TOMLDecodeError") },
});

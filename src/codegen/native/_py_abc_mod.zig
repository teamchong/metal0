/// Python _py_abc module - Pure Python ABC implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "a_b_c_meta", h.c(".{ ._abc_registry = .{}, ._abc_cache = .{}, ._abc_negative_cache = .{} }") },
    .{ "get_cache_token", h.I64(0) },
});

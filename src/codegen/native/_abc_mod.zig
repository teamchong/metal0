/// Python _abc module - Internal ABC support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_cache_token", h.c("@as(u64, 0)") }, .{ "_abc_init", h.c("{}") },
    .{ "_abc_register", h.passN(1, "null") }, .{ "_abc_instancecheck", h.c("false") },
    .{ "_abc_subclasscheck", h.c("false") }, .{ "_get_dump", h.c(".{ &[_]type{}, &[_]type{}, &[_]type{} }") },
    .{ "_reset_registry", h.c("{}") }, .{ "_reset_caches", h.c("{}") },
});

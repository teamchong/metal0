/// Python _warnings module - Internal warnings support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "warn", h.c("{}") }, .{ "warn_explicit", h.c("{}") }, .{ "_filters_mutated", h.c("{}") },
    .{ "filters", h.c("&[_]@TypeOf(.{}){}") }, .{ "_defaultaction", h.c("\"default\"") }, .{ "_onceregistry", h.c(".{}") },
});

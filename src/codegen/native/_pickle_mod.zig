/// Python _pickle module - C accelerator for pickle (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", h.discard("\"\"") }, .{ "dump", h.c("{}") }, .{ "loads", h.discard("null") }, .{ "load", h.c("null") },
    .{ "Pickler", h.c(".{ .protocol = 4 }") }, .{ "Unpickler", h.c(".{}") }, .{ "HIGHEST_PROTOCOL", h.I32(5) }, .{ "DEFAULT_PROTOCOL", h.I32(4) },
    .{ "PickleError", h.err("PickleError") }, .{ "PicklingError", h.err("PicklingError") }, .{ "UnpicklingError", h.err("UnpicklingError") },
});

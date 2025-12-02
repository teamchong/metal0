/// Python _threading_local module - Internal threading.local support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "local", h.c(".{}") }, .{ "_localimpl", h.c(".{ .key = \"\", .dicts = .{}, .localargs = .{}, .localkwargs = .{}, .loclock = .{} }") },
    .{ "_localimpl_create_dict", h.c(".{}") }, .{ "__init__", h.c("{}") },
    .{ "__getattribute__", h.c("null") }, .{ "__setattr__", h.c("{}") }, .{ "__delattr__", h.c("{}") },
});

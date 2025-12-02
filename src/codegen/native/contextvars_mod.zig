/// Python contextvars module - Context Variables
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ContextVar", h.wrap("blk: { const name = ", "; break :blk .{ .name = name, .value = null }; }", ".{ .name = \"\", .value = null }") }, .{ "Token", h.c(".{ .var = null, .old_value = null }") },
    .{ "Context", h.c(".{ .data = metal0_runtime.PyDict([]const u8, ?anyopaque).init() }") },
    .{ "copy_context", h.c(".{ .data = metal0_runtime.PyDict([]const u8, ?anyopaque).init() }") },
});

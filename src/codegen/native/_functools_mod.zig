/// Python _functools module - C accelerator for functools (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reduce", h.wrap2("blk: { var result = ", "; const items = ", "; _ = items; break :blk result; }", "null") },
    .{ "cmp_to_key", h.wrap("blk: { const cmp = ", "; break :blk .{ .cmp = cmp }; }", ".{}") },
});

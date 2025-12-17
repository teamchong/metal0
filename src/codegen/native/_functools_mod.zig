/// Python _functools module - C accelerator for functools (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reduce", h.wrap2Blk("red", "_ = __v1;", "__v0", "null") },
    .{ "cmp_to_key", h.structBlk("ctk", ".cmp = __v", ".{}") },
});

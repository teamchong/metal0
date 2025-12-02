/// Python _codecs_kr module - Korean codecs
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcodec", h.c(".{ .name = \"euc_kr\" }") },
});

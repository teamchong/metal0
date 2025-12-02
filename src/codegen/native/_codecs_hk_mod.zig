/// Python _codecs_hk module - Hong Kong codecs
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcodec", h.c(".{ .name = \"big5hkscs\" }") },
});

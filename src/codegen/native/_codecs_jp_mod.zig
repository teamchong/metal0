/// Python _codecs_jp module - Japanese codecs
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcodec", h.c(".{ .name = \"shift_jis\" }") },
});

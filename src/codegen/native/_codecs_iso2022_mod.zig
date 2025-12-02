/// Python _codecs_iso2022 module - ISO 2022 codecs
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcodec", h.c(".{ .name = \"iso2022_jp\" }") },
});

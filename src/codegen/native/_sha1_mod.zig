/// Python _sha1 module - Internal SHA1 support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sha1", h.c(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }") }, .{ "update", h.c("{}") },
    .{ "digest", h.c("\"\\x00\" ** 20") }, .{ "hexdigest", h.c("\"0\" ** 40") }, .{ "copy", h.c(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }") },
});

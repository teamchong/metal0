/// Python _md5 module - Internal MD5 support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "md5", h.c(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }") }, .{ "update", h.c("{}") },
    .{ "digest", h.c("\"\\x00\" ** 16") }, .{ "hexdigest", h.c("\"0\" ** 32") }, .{ "copy", h.c(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }") },
});

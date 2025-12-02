/// Python _sha2 module - Internal SHA2 support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sha224", h.c(".{ .name = \"sha224\", .digest_size = 28, .block_size = 64 }") }, .{ "sha256", h.c(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }") },
    .{ "sha384", h.c(".{ .name = \"sha384\", .digest_size = 48, .block_size = 128 }") }, .{ "sha512", h.c(".{ .name = \"sha512\", .digest_size = 64, .block_size = 128 }") },
    .{ "update", h.c("{}") }, .{ "digest", h.c("\"\\x00\" ** 32") }, .{ "hexdigest", h.c("\"0\" ** 64") }, .{ "copy", h.c(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }") },
});

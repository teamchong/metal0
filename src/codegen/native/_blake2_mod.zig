/// Python _blake2 module - BLAKE2 hash functions (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "blake2b", h.c(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }") },
    .{ "blake2s", h.c(".{ .name = \"blake2s\", .digest_size = 32, .block_size = 64 }") },
    .{ "update", h.c("{}") }, .{ "digest", h.c("\"\"") }, .{ "hexdigest", h.c("\"0\" ** 128") },
    .{ "copy", h.c(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }") },
    .{ "BLAKE2B_SALT_SIZE", h.U32(16) }, .{ "BLAKE2B_PERSON_SIZE", h.U32(16) },
    .{ "BLAKE2B_MAX_KEY_SIZE", h.U32(64) }, .{ "BLAKE2B_MAX_DIGEST_SIZE", h.U32(64) },
    .{ "BLAKE2S_SALT_SIZE", h.U32(8) }, .{ "BLAKE2S_PERSON_SIZE", h.U32(8) },
    .{ "BLAKE2S_MAX_KEY_SIZE", h.U32(32) }, .{ "BLAKE2S_MAX_DIGEST_SIZE", h.U32(32) },
});

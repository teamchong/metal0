/// Python _sha3 module - Internal SHA3 support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sha3_224", h.c(".{ .name = \"sha3_224\", .digest_size = 28, .block_size = 144 }") }, .{ "sha3_256", h.c(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }") },
    .{ "sha3_384", h.c(".{ .name = \"sha3_384\", .digest_size = 48, .block_size = 104 }") }, .{ "sha3_512", h.c(".{ .name = \"sha3_512\", .digest_size = 64, .block_size = 72 }") },
    .{ "shake128", h.c(".{ .name = \"shake_128\", .digest_size = 0, .block_size = 168 }") }, .{ "shake256", h.c(".{ .name = \"shake_256\", .digest_size = 0, .block_size = 136 }") },
    .{ "update", h.c("{}") }, .{ "digest", h.c("\"\\x00\" ** 32") }, .{ "hexdigest", h.c("\"0\" ** 64") }, .{ "copy", h.c(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }") },
    .{ "shake_digest", h.c("\"\"") }, .{ "shake_hexdigest", h.c("\"\"") },
});

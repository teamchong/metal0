/// Python crypt module - Function to check Unix passwords
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "crypt", h.discardBlk("crypt", "\"$6$rounds=5000$salt$hash\"", "\"\"") }, .{ "mksalt", h.c("\"$6$rounds=5000$\"") },
    .{ "METHOD_SHA512", h.c(".{ .name = \"SHA512\", .ident = \"$6$\", .salt_chars = 16, .total_size = 106 }") },
    .{ "METHOD_SHA256", h.c(".{ .name = \"SHA256\", .ident = \"$5$\", .salt_chars = 16, .total_size = 63 }") },
    .{ "METHOD_BLOWFISH", h.c(".{ .name = \"BLOWFISH\", .ident = \"$2b$\", .salt_chars = 22, .total_size = 59 }") },
    .{ "METHOD_MD5", h.c(".{ .name = \"MD5\", .ident = \"$1$\", .salt_chars = 8, .total_size = 34 }") },
    .{ "METHOD_CRYPT", h.c(".{ .name = \"CRYPT\", .ident = \"\", .salt_chars = 2, .total_size = 13 }") },
    .{ "methods", h.c("runtime.NativeList.init()") },
});

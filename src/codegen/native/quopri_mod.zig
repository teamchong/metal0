/// Python quopri module - Quoted-Printable encoding/decoding
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", h.c("{}") }, .{ "decode", h.c("{}") },
    .{ "encodestring", h.pass("\"\"") }, .{ "decodestring", h.pass("\"\"") },
});

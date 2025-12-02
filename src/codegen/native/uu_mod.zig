/// Python uu module - UUencode/decode
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", h.c("{}") },
    .{ "decode", h.c("{}") },
    .{ "Error", h.err("UuError") },
});

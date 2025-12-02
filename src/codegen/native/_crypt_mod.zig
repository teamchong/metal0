/// Python _crypt module - Unix crypt() password hashing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "crypt", h.c("\"\"") },
});

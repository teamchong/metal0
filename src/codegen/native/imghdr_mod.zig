/// Python imghdr module - Image file type determination
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "what", h.c("@as(?[]const u8, null)") },
    .{ "tests", h.c("&[_]*const fn ([]const u8, *anyopaque) ?[]const u8{}") },
});

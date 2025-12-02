/// Python xdrlib module - XDR data encoding/decoding
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Packer", h.c(".{ .data = \"\" }") },
    .{ "Unpacker", h.wrap("blk: { const data = ", "; break :blk .{ .data = data, .pos = @as(i32, 0) }; }", ".{ .data = \"\", .pos = @as(i32, 0) }") },
    .{ "Error", h.err("XdrError") },
    .{ "ConversionError", h.err("ConversionError") },
});

/// Python xdrlib module - XDR data encoding/decoding
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Packer", h.c(".{ .data = \"\" }") },
    .{ "Unpacker", h.structBlk("xdr", ".data = __v, .pos = @as(i32, 0)", ".{ .data = \"\", .pos = @as(i32, 0) }") },
    .{ "Error", h.err("XdrError") },
    .{ "ConversionError", h.err("ConversionError") },
});

/// Python _bz2 module - Internal BZ2 support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "b_z2_compressor", h.c(".{ .compresslevel = 9 }") }, .{ "b_z2_decompressor", h.c(".{ .eof = false, .needs_input = true, .unused_data = \"\" }") },
    .{ "compress", h.c("\"\"") }, .{ "flush", h.c("\"\"") }, .{ "decompress", h.c("\"\"") },
});

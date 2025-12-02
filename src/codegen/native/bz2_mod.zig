/// Python bz2 module - Bzip2 compression library
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", h.pass("\"\"") }, .{ "decompress", h.pass("\"\"") }, .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "BZ2File", h.c("@as(?*anyopaque, null)") },
    .{ "BZ2Compressor", h.c(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }") },
    .{ "BZ2Decompressor", h.c(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }") },
});

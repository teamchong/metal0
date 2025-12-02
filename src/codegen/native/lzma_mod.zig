/// Python lzma module - LZMA/XZ compression
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", h.pass("\"\"") }, .{ "decompress", h.pass("\"\"") },
    .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "LZMAFile", h.c("@as(?*anyopaque, null)") },
    .{ "LZMACompressor", h.c(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }") },
    .{ "LZMADecompressor", h.c(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }") },
    .{ "is_check_supported", h.c("true") },
    .{ "FORMAT_AUTO", h.I32(0) }, .{ "CHECK_NONE", h.I32(0) },
    .{ "FORMAT_XZ", h.I32(1) }, .{ "CHECK_CRC32", h.I32(1) },
    .{ "FORMAT_ALONE", h.I32(2) }, .{ "FORMAT_RAW", h.I32(3) },
    .{ "CHECK_CRC64", h.I32(4) }, .{ "PRESET_DEFAULT", h.I32(6) },
    .{ "CHECK_SHA256", h.I32(10) }, .{ "CHECK_ID_MAX", h.I32(15) }, .{ "CHECK_UNKNOWN", h.I32(16) },
    .{ "PRESET_EXTREME", h.hex32(0x80000000) },
    .{ "FILTER_LZMA1", h.c("@as(i64, 0x4000000000000001)") }, .{ "FILTER_LZMA2", h.c("@as(i64, 0x21)") },
    .{ "FILTER_DELTA", h.c("@as(i64, 0x03)") }, .{ "FILTER_X86", h.c("@as(i64, 0x04)") },
    .{ "FILTER_ARM", h.c("@as(i64, 0x07)") }, .{ "FILTER_ARMTHUMB", h.c("@as(i64, 0x08)") }, .{ "FILTER_SPARC", h.c("@as(i64, 0x09)") },
});

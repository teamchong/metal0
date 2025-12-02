/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", h.wrap("try zlib.compress(", ", __global_allocator)", "\"\"") },
    .{ "decompress", h.wrap("try zlib.decompressAuto(", ", __global_allocator)", "\"\"") },
    .{ "compressobj", h.wrap("zlib.compressobj.init(@intCast(", "))", "zlib.compressobj.init(-1)") },
    .{ "decompressobj", h.c("zlib.decompressobj.init()") },
    .{ "crc32", h.wrap2("zlib.crc32(", ", @intCast(", "))", "@as(u32, 0)") },
    .{ "adler32", h.wrap2("zlib.adler32(", ", @intCast(", "))", "@as(u32, 1)") },
    .{ "crc32_combine", h.wrap3("zlib.crc32_combine(@intCast(", "), @intCast(", "), @intCast(", "))", "@as(u32, 0)") },
    .{ "adler32_combine", h.wrap3("zlib.adler32_combine(@intCast(", "), @intCast(", "), @intCast(", "))", "@as(u32, 0)") },
    .{ "MAX_WBITS", h.I32(15) }, .{ "DEFLATED", h.I32(8) }, .{ "DEF_BUF_SIZE", h.I32(16384) }, .{ "DEF_MEM_LEVEL", h.I32(8) },
    .{ "Z_DEFAULT_STRATEGY", h.I32(0) }, .{ "Z_FILTERED", h.I32(1) }, .{ "Z_HUFFMAN_ONLY", h.I32(2) }, .{ "Z_RLE", h.I32(3) }, .{ "Z_FIXED", h.I32(4) },
    .{ "Z_NO_COMPRESSION", h.I32(0) }, .{ "Z_BEST_SPEED", h.I32(1) }, .{ "Z_BEST_COMPRESSION", h.I32(9) }, .{ "Z_DEFAULT_COMPRESSION", h.I32(-1) },
    .{ "Z_NO_FLUSH", h.I32(0) }, .{ "Z_PARTIAL_FLUSH", h.I32(1) }, .{ "Z_SYNC_FLUSH", h.I32(2) }, .{ "Z_FULL_FLUSH", h.I32(3) }, .{ "Z_FINISH", h.I32(4) }, .{ "Z_BLOCK", h.I32(5) }, .{ "Z_TREES", h.I32(6) },
    .{ "ZLIB_VERSION", h.c("\"1.2.13\"") }, .{ "ZLIB_RUNTIME_VERSION", h.c("zlib.zlibVersion()") }, .{ "error", h.err("ZlibError") },
});

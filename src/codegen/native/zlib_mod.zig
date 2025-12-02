/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", genCompress }, .{ "decompress", genDecompress },
    .{ "compressobj", genCompressobj }, .{ "decompressobj", h.c("zlib.decompressobj.init()") },
    .{ "crc32", genCrc32 }, .{ "adler32", genAdler32 },
    .{ "crc32_combine", genCrc32Combine }, .{ "adler32_combine", genAdler32Combine },
    .{ "MAX_WBITS", h.I32(15) }, .{ "DEFLATED", h.I32(8) }, .{ "DEF_BUF_SIZE", h.I32(16384) }, .{ "DEF_MEM_LEVEL", h.I32(8) },
    .{ "Z_DEFAULT_STRATEGY", h.I32(0) }, .{ "Z_FILTERED", h.I32(1) }, .{ "Z_HUFFMAN_ONLY", h.I32(2) }, .{ "Z_RLE", h.I32(3) }, .{ "Z_FIXED", h.I32(4) },
    .{ "Z_NO_COMPRESSION", h.I32(0) }, .{ "Z_BEST_SPEED", h.I32(1) }, .{ "Z_BEST_COMPRESSION", h.I32(9) }, .{ "Z_DEFAULT_COMPRESSION", h.I32(-1) },
    .{ "Z_NO_FLUSH", h.I32(0) }, .{ "Z_PARTIAL_FLUSH", h.I32(1) }, .{ "Z_SYNC_FLUSH", h.I32(2) }, .{ "Z_FULL_FLUSH", h.I32(3) }, .{ "Z_FINISH", h.I32(4) }, .{ "Z_BLOCK", h.I32(5) }, .{ "Z_TREES", h.I32(6) },
    .{ "ZLIB_VERSION", h.c("\"1.2.13\"") }, .{ "ZLIB_RUNTIME_VERSION", h.c("zlib.zlibVersion()") }, .{ "error", h.err("ZlibError") },
});

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("try zlib.compress("); try self.genExpr(args[0]); try self.emit(", __global_allocator)"); } else try self.emit("\"\"");
}
fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("try zlib.decompressAuto("); try self.genExpr(args[0]); try self.emit(", __global_allocator)"); } else try self.emit("\"\"");
}
fn genCompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("zlib.compressobj.init(");
    if (args.len > 0) { try self.emit("@intCast("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("-1");
    try self.emit(")");
}
fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("zlib.crc32("); try self.genExpr(args[0]); if (args.len > 1) { try self.emit(", @intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(", 0"); try self.emit(")"); } else try self.emit("@as(u32, 0)");
}
fn genAdler32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("zlib.adler32("); try self.genExpr(args[0]); if (args.len > 1) { try self.emit(", @intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(", 1"); try self.emit(")"); } else try self.emit("@as(u32, 1)");
}
fn genCrc32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) { try self.emit("zlib.crc32_combine(@intCast("); try self.genExpr(args[0]); try self.emit("), @intCast("); try self.genExpr(args[1]); try self.emit("), @intCast("); try self.genExpr(args[2]); try self.emit("))"); } else try self.emit("@as(u32, 0)");
}
fn genAdler32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) { try self.emit("zlib.adler32_combine(@intCast("); try self.genExpr(args[0]); try self.emit("), @intCast("); try self.genExpr(args[1]); try self.emit("), @intCast("); try self.genExpr(args[2]); try self.emit("))"); } else try self.emit("@as(u32, 0)");
}

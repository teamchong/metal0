/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genCompress }, .{ "decompress", genDecompress },
    .{ "compressobj", genCompressobj }, .{ "decompressobj", genConst("zlib.decompressobj.init()") },
    .{ "crc32", genCrc32 }, .{ "adler32", genAdler32 },
    .{ "crc32_combine", genCrc32Combine }, .{ "adler32_combine", genAdler32Combine },
    .{ "MAX_WBITS", genConst("@as(i32, 15)") }, .{ "DEFLATED", genConst("@as(i32, 8)") }, .{ "DEF_BUF_SIZE", genConst("@as(i32, 16384)") }, .{ "DEF_MEM_LEVEL", genConst("@as(i32, 8)") },
    .{ "Z_DEFAULT_STRATEGY", genConst("@as(i32, 0)") }, .{ "Z_FILTERED", genConst("@as(i32, 1)") }, .{ "Z_HUFFMAN_ONLY", genConst("@as(i32, 2)") }, .{ "Z_RLE", genConst("@as(i32, 3)") }, .{ "Z_FIXED", genConst("@as(i32, 4)") },
    .{ "Z_NO_COMPRESSION", genConst("@as(i32, 0)") }, .{ "Z_BEST_SPEED", genConst("@as(i32, 1)") }, .{ "Z_BEST_COMPRESSION", genConst("@as(i32, 9)") }, .{ "Z_DEFAULT_COMPRESSION", genConst("@as(i32, -1)") },
    .{ "Z_NO_FLUSH", genConst("@as(i32, 0)") }, .{ "Z_PARTIAL_FLUSH", genConst("@as(i32, 1)") }, .{ "Z_SYNC_FLUSH", genConst("@as(i32, 2)") }, .{ "Z_FULL_FLUSH", genConst("@as(i32, 3)") }, .{ "Z_FINISH", genConst("@as(i32, 4)") }, .{ "Z_BLOCK", genConst("@as(i32, 5)") }, .{ "Z_TREES", genConst("@as(i32, 6)") },
    .{ "ZLIB_VERSION", genConst("\"1.2.13\"") }, .{ "ZLIB_RUNTIME_VERSION", genConst("zlib.zlibVersion()") }, .{ "error", genConst("error.ZlibError") },
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

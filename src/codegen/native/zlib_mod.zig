/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genCompress }, .{ "decompress", genDecompress },
    .{ "compressobj", genCompressobj }, .{ "decompressobj", genDecompressobj },
    .{ "crc32", genCrc32 }, .{ "adler32", genAdler32 },
    .{ "crc32_combine", genCrc32Combine }, .{ "adler32_combine", genAdler32Combine },
    .{ "MAX_WBITS", genI32(15) }, .{ "DEFLATED", genI32(8) }, .{ "DEF_BUF_SIZE", genI32(16384) }, .{ "DEF_MEM_LEVEL", genI32(8) },
    .{ "Z_DEFAULT_STRATEGY", genI32(0) }, .{ "Z_FILTERED", genI32(1) }, .{ "Z_HUFFMAN_ONLY", genI32(2) }, .{ "Z_RLE", genI32(3) }, .{ "Z_FIXED", genI32(4) },
    .{ "Z_NO_COMPRESSION", genI32(0) }, .{ "Z_BEST_SPEED", genI32(1) }, .{ "Z_BEST_COMPRESSION", genI32(9) }, .{ "Z_DEFAULT_COMPRESSION", genI32(-1) },
    .{ "Z_NO_FLUSH", genI32(0) }, .{ "Z_PARTIAL_FLUSH", genI32(1) }, .{ "Z_SYNC_FLUSH", genI32(2) }, .{ "Z_FULL_FLUSH", genI32(3) }, .{ "Z_FINISH", genI32(4) }, .{ "Z_BLOCK", genI32(5) }, .{ "Z_TREES", genI32(6) },
    .{ "ZLIB_VERSION", genVersion }, .{ "ZLIB_RUNTIME_VERSION", genRuntimeVersion }, .{ "error", genError },
});

fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"1.2.13\""); }
fn genRuntimeVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "zlib.zlibVersion()"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ZlibError"); }

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
fn genDecompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("zlib.decompressobj.init()"); }
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

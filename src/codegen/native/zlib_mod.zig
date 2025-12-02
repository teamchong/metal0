/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genCompress }, .{ "decompress", genDecompress },
    .{ "compressobj", genCompressobj }, .{ "decompressobj", genDecompressobj },
    .{ "crc32", genCrc32 }, .{ "adler32", genAdler32 },
    .{ "crc32_combine", genCrc32Combine }, .{ "adler32_combine", genAdler32Combine },
    .{ "MAX_WBITS", genI32_15 }, .{ "DEFLATED", genI32_8 },
    .{ "DEF_BUF_SIZE", genI32_16384 }, .{ "DEF_MEM_LEVEL", genI32_8 },
    .{ "Z_DEFAULT_STRATEGY", genI32_0 }, .{ "Z_FILTERED", genI32_1 }, .{ "Z_HUFFMAN_ONLY", genI32_2 },
    .{ "Z_RLE", genI32_3 }, .{ "Z_FIXED", genI32_4 },
    .{ "Z_NO_COMPRESSION", genI32_0 }, .{ "Z_BEST_SPEED", genI32_1 }, .{ "Z_BEST_COMPRESSION", genI32_9 },
    .{ "Z_DEFAULT_COMPRESSION", genI32_Neg1 },
    .{ "Z_NO_FLUSH", genI32_0 }, .{ "Z_PARTIAL_FLUSH", genI32_1 }, .{ "Z_SYNC_FLUSH", genI32_2 },
    .{ "Z_FULL_FLUSH", genI32_3 }, .{ "Z_FINISH", genI32_4 }, .{ "Z_BLOCK", genI32_5 }, .{ "Z_TREES", genI32_6 },
    .{ "ZLIB_VERSION", genVersion }, .{ "ZLIB_RUNTIME_VERSION", genRuntimeVersion },
    .{ "error", genError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genI32_15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 15)"); }
fn genI32_16384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16384)"); }
fn genI32_Neg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }
fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"1.2.13\""); }
fn genRuntimeVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "zlib.zlibVersion()"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ZlibError"); }

// Functions with args
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
    if (args.len > 0) {
        try self.emit("zlib.crc32("); try self.genExpr(args[0]);
        if (args.len > 1) { try self.emit(", @intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(", 0");
        try self.emit(")");
    } else try self.emit("@as(u32, 0)");
}

fn genAdler32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("zlib.adler32("); try self.genExpr(args[0]);
        if (args.len > 1) { try self.emit(", @intCast("); try self.genExpr(args[1]); try self.emit(")"); } else try self.emit(", 1");
        try self.emit(")");
    } else try self.emit("@as(u32, 1)");
}

fn genCrc32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("zlib.crc32_combine(@intCast("); try self.genExpr(args[0]);
        try self.emit("), @intCast("); try self.genExpr(args[1]);
        try self.emit("), @intCast("); try self.genExpr(args[2]); try self.emit("))");
    } else try self.emit("@as(u32, 0)");
}

fn genAdler32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("zlib.adler32_combine(@intCast("); try self.genExpr(args[0]);
        try self.emit("), @intCast("); try self.genExpr(args[1]);
        try self.emit("), @intCast("); try self.genExpr(args[2]); try self.emit("))");
    } else try self.emit("@as(u32, 0)");
}

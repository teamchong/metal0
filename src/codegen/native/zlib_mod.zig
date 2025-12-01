/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genCompress },
    .{ "decompress", genDecompress },
    .{ "compressobj", genCompressobj },
    .{ "decompressobj", genDecompressobj },
    .{ "crc32", genCrc32 },
    .{ "adler32", genAdler32 },
    .{ "MAX_WBITS", genMAX_WBITS },
    .{ "DEFLATED", genDEFLATED },
    .{ "DEF_BUF_SIZE", genDEF_BUF_SIZE },
    .{ "DEF_MEM_LEVEL", genDEF_MEM_LEVEL },
    .{ "Z_DEFAULT_STRATEGY", genZ_DEFAULT_STRATEGY },
    .{ "Z_FILTERED", genZ_FILTERED },
    .{ "Z_HUFFMAN_ONLY", genZ_HUFFMAN_ONLY },
    .{ "Z_RLE", genZ_RLE },
    .{ "Z_FIXED", genZ_FIXED },
    .{ "Z_NO_COMPRESSION", genZ_NO_COMPRESSION },
    .{ "Z_BEST_SPEED", genZ_BEST_SPEED },
    .{ "Z_BEST_COMPRESSION", genZ_BEST_COMPRESSION },
    .{ "Z_DEFAULT_COMPRESSION", genZ_DEFAULT_COMPRESSION },
    .{ "ZLIB_VERSION", genZLIB_VERSION },
    .{ "ZLIB_RUNTIME_VERSION", genZLIB_RUNTIME_VERSION },
    .{ "error", genError },
    .{ "crc32_combine", genCrc32Combine },
    .{ "adler32_combine", genAdler32Combine },
    .{ "Z_NO_FLUSH", genZ_NO_FLUSH },
    .{ "Z_PARTIAL_FLUSH", genZ_PARTIAL_FLUSH },
    .{ "Z_SYNC_FLUSH", genZ_SYNC_FLUSH },
    .{ "Z_FULL_FLUSH", genZ_FULL_FLUSH },
    .{ "Z_FINISH", genZ_FINISH },
    .{ "Z_BLOCK", genZ_BLOCK },
    .{ "Z_TREES", genZ_TREES },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Compression Functions
// ============================================================================

/// Generate zlib.compress(data, level=-1)
/// Calls C interop zlib.compress function
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("try zlib.compress(");
        try self.genExpr(args[0]);
        try self.emit(", __global_allocator)");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate zlib.decompress(data, wbits=MAX_WBITS, bufsize=DEF_BUF_SIZE)
/// Calls C interop zlib.decompressAuto function
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("try zlib.decompressAuto(");
        try self.genExpr(args[0]);
        try self.emit(", __global_allocator)");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate zlib.compressobj(level=-1, method=DEFLATED, wbits=MAX_WBITS, memLevel=DEF_MEM_LEVEL, strategy=Z_DEFAULT_STRATEGY)
/// Returns a compression object that supports .compress() and .flush() methods
pub fn genCompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("zlib.compressobj.init(");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("-1"); // Z_DEFAULT_COMPRESSION
    }
    try self.emit(")");
}

/// Generate zlib.decompressobj(wbits=MAX_WBITS)
/// Returns a decompression object that supports .decompress() and .flush() methods
pub fn genDecompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("zlib.decompressobj.init()");
}

// ============================================================================
// CRC and Adler Functions
// ============================================================================

/// Generate zlib.crc32(data, value=0)
pub fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("zlib.crc32(");
        try self.genExpr(args[0]);
        if (args.len > 1) {
            try self.emit(", @intCast(");
            try self.genExpr(args[1]);
            try self.emit(")");
        } else {
            try self.emit(", 0");
        }
        try self.emit(")");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate zlib.adler32(data, value=1)
pub fn genAdler32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("zlib.adler32(");
        try self.genExpr(args[0]);
        if (args.len > 1) {
            try self.emit(", @intCast(");
            try self.genExpr(args[1]);
            try self.emit(")");
        } else {
            try self.emit(", 1");
        }
        try self.emit(")");
    } else {
        try self.emit("@as(u32, 1)");
    }
}

// ============================================================================
// Constants
// ============================================================================

pub fn genMAX_WBITS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 15)");
}

pub fn genDEFLATED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genDEF_BUF_SIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16384)");
}

pub fn genDEF_MEM_LEVEL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genZ_DEFAULT_STRATEGY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genZ_FILTERED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genZ_HUFFMAN_ONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genZ_RLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genZ_FIXED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genZ_NO_COMPRESSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genZ_BEST_SPEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genZ_BEST_COMPRESSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

pub fn genZ_DEFAULT_COMPRESSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

// ============================================================================
// Version Info
// ============================================================================

pub fn genZLIB_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"1.2.13\"");
}

pub fn genZLIB_RUNTIME_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("zlib.zlibVersion()");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZlibError");
}

// ============================================================================
// Checksum Combine Functions
// ============================================================================

/// Generate zlib.crc32_combine(crc1, crc2, len2)
pub fn genCrc32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("zlib.crc32_combine(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("), @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), @intCast(");
        try self.genExpr(args[2]);
        try self.emit("))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate zlib.adler32_combine(adler1, adler2, len2)
pub fn genAdler32Combine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit("zlib.adler32_combine(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("), @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), @intCast(");
        try self.genExpr(args[2]);
        try self.emit("))");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

// ============================================================================
// Flush Constants
// ============================================================================

pub fn genZ_NO_FLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genZ_PARTIAL_FLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genZ_SYNC_FLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genZ_FULL_FLUSH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genZ_FINISH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genZ_BLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genZ_TREES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

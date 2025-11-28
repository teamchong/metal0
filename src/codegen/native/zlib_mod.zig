/// Python zlib module - Compression/decompression using zlib library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Compression Functions
// ============================================================================

/// Generate zlib.compress(data, level=-1)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; var compressed = std.ArrayList(u8).init(__global_allocator); var comp = std.compress.zlib.compressor(.default, compressed.writer()) catch break :blk \"\"; _ = comp.write(data) catch break :blk \"\"; comp.finish() catch {}; break :blk compressed.items; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate zlib.decompress(data, wbits=MAX_WBITS, bufsize=DEF_BUF_SIZE)
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; var fbs = std.io.fixedBufferStream(data); var decompressed = std.ArrayList(u8).init(__global_allocator); var decomp = std.compress.zlib.decompressor(fbs.reader()) catch break :blk \"\"; while (decomp.read(&[_]u8{0} ** 4096)) |buf| { if (buf.len == 0) break; decompressed.appendSlice(buf) catch break; } else |_| {} break :blk decompressed.items; }");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate zlib.compressobj(level=-1, method=DEFLATED, wbits=MAX_WBITS, memLevel=DEF_MEM_LEVEL, strategy=Z_DEFAULT_STRATEGY)
pub fn genCompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .level = 6 }");
}

/// Generate zlib.decompressobj(wbits=MAX_WBITS)
pub fn genDecompressobj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// CRC and Adler Functions
// ============================================================================

/// Generate zlib.crc32(data, value=0)
pub fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk @as(u32, std.hash.Crc32.hash(data)); }");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate zlib.adler32(data, value=1)
pub fn genAdler32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; var a: u32 = 1; var b: u32 = 0; for (data) |byte| { a = (a + byte) % 65521; b = (b + a) % 65521; } break :blk (b << 16) | a; }");
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
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZlibError");
}

/// Python lzma module - LZMA/XZ compression
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate lzma.compress(data, format=FORMAT_XZ, ...)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate lzma.decompress(data, format=FORMAT_AUTO, ...)
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate lzma.open(filename, mode='rb', ...)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate lzma.LZMAFile(filename, mode='r', ...)
pub fn genLZMAFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate lzma.LZMACompressor(format=FORMAT_XZ, ...)
pub fn genLZMACompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }");
}

/// Generate lzma.LZMADecompressor(format=FORMAT_AUTO, ...)
pub fn genLZMADecompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }");
}

/// Generate lzma.is_check_supported(check)
pub fn genIs_check_supported(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

// ============================================================================
// Format constants
// ============================================================================

pub fn genFORMAT_AUTO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genFORMAT_XZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genFORMAT_ALONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genFORMAT_RAW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

// ============================================================================
// Check constants (integrity check)
// ============================================================================

pub fn genCHECK_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genCHECK_CRC32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genCHECK_CRC64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genCHECK_SHA256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

pub fn genCHECK_ID_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 15)");
}

pub fn genCHECK_UNKNOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

// ============================================================================
// Preset constants
// ============================================================================

pub fn genPRESET_DEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genPRESET_EXTREME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x80000000)");
}

// ============================================================================
// Filter IDs
// ============================================================================

pub fn genFILTER_LZMA1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x4000000000000001)");
}

pub fn genFILTER_LZMA2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x21)");
}

pub fn genFILTER_DELTA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x03)");
}

pub fn genFILTER_X86(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x04)");
}

pub fn genFILTER_ARM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x07)");
}

pub fn genFILTER_ARMTHUMB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x08)");
}

pub fn genFILTER_SPARC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x09)");
}

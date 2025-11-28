/// Python bz2 module - Bzip2 compression library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate bz2.compress(data, compresslevel=9)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate bz2.decompress(data)
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate bz2.open(filename, mode='rb', compresslevel=9, ...)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate bz2.BZ2File(filename, mode='r', ...)
pub fn genBZ2File(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate bz2.BZ2Compressor(compresslevel=9)
pub fn genBZ2Compressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }");
}

/// Generate bz2.BZ2Decompressor()
pub fn genBZ2Decompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }");
}

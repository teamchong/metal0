/// Python _bz2 module - Internal BZ2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "b_z2_compressor", genBZ2Compressor },
    .{ "b_z2_decompressor", genBZ2Decompressor },
    .{ "compress", genCompress },
    .{ "flush", genFlush },
    .{ "decompress", genDecompress },
});

/// Generate _bz2.BZ2Compressor(compresslevel=9)
pub fn genBZ2Compressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compresslevel = 9 }");
}

/// Generate _bz2.BZ2Decompressor()
pub fn genBZ2Decompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .eof = false, .needs_input = true, .unused_data = \"\" }");
}

/// Generate BZ2Compressor.compress(data)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate BZ2Compressor.flush()
pub fn genFlush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate BZ2Decompressor.decompress(data, max_length=-1)
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

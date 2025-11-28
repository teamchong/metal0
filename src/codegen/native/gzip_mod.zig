/// Python gzip module - GZIP compression
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate gzip.compress(data, compresslevel=9) -> compressed bytes
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("gzip_compress_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _compressed = std.ArrayList(u8).init(allocator);\n");
    try self.emitIndent();
    try self.emit("var _compressor = std.compress.gzip.compressor(_compressed.writer(allocator), .{}) catch break :gzip_compress_blk _data;\n");
    try self.emitIndent();
    try self.emit("_ = _compressor.write(_data) catch break :gzip_compress_blk _data;\n");
    try self.emitIndent();
    try self.emit("_compressor.close() catch {};\n");
    try self.emitIndent();
    try self.emit("break :gzip_compress_blk _compressed.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate gzip.decompress(data) -> decompressed bytes
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("gzip_decompress_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _fbs = std.io.fixedBufferStream(_data);\n");
    try self.emitIndent();
    try self.emit("var _decompressor = std.compress.gzip.decompressor(_fbs.reader()) catch break :gzip_decompress_blk _data;\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(u8).init(allocator);\n");
    try self.emitIndent();
    try self.emit("while (true) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var buf: [4096]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("const n = _decompressor.read(&buf) catch break;\n");
    try self.emitIndent();
    try self.emit("if (n == 0) break;\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(allocator, buf[0..n]) catch break;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :gzip_decompress_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate gzip.open(filename, mode='rb', compresslevel=9) -> file object
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("gzip_open_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _mode: []const u8 = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"rb\"");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _mode;\n");
    try self.emitIndent();
    try self.emit("break :gzip_open_blk struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("path: []const u8,\n");
    try self.emitIndent();
    try self.emit("buffer: std.ArrayList(u8),\n");
    try self.emitIndent();
    try self.emit("pub fn init(p: []const u8) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @This(){ .path = p, .buffer = std.ArrayList(u8).init(allocator) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().openFile(self.path, .{}) catch return \"\";\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return \"\";\n");
    try self.emitIndent();
    try self.emit("return content;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn write(self: *@This(), data: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.buffer.appendSlice(allocator, data) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.buffer.items.len > 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().createFile(self.path, .{}) catch return;\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("_ = file.write(self.buffer.items) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.close(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}.init(_path);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate gzip.GzipFile(filename, mode='rb', compresslevel=9) -> GzipFile
pub fn genGzipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOpen(self, args);
}

/// Generate gzip.BadGzipFile exception
pub fn genBadGzipFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"BadGzipFile\"");
}

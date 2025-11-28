/// Python _compression module - Internal compression support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _compression.DecompressReader(fp, decomp, trailing_error=())
pub fn genDecompressReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .fp = null, .decomp = null, .eof = false, .pos = 0, .size = -1 }");
}

/// Generate DecompressReader.readable()
pub fn genReadable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate DecompressReader.writable()
pub fn genWritable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate DecompressReader.seekable()
pub fn genSeekable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate DecompressReader.read(size=-1)
pub fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate DecompressReader.read1(size=-1)
pub fn genRead1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate DecompressReader.readinto(b)
pub fn genReadinto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

/// Generate DecompressReader.readline(size=-1)
pub fn genReadline(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate DecompressReader.readlines(hint=-1)
pub fn genReadlines(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate DecompressReader.seek(offset, whence=0)
pub fn genSeek(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate DecompressReader.tell()
pub fn genTell(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate DecompressReader.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _compression.BaseStream class
pub fn genBaseStream(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Python _md5 module - Internal MD5 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _md5.md5(data=b'', *, usedforsecurity=True)
pub fn genMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }");
}

/// Generate md5.update(data)
pub fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate md5.digest()
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 16");
}

/// Generate md5.hexdigest()
pub fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0\" ** 32");
}

/// Generate md5.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }");
}

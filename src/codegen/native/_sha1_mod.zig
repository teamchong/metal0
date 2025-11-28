/// Python _sha1 module - Internal SHA1 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sha1.sha1(data=b'', *, usedforsecurity=True)
pub fn genSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }");
}

/// Generate sha1.update(data)
pub fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sha1.digest()
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 20");
}

/// Generate sha1.hexdigest()
pub fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0\" ** 40");
}

/// Generate sha1.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }");
}

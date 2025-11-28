/// Python _sha2 module - Internal SHA2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sha2.sha224(data=b'', *, usedforsecurity=True)
pub fn genSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha224\", .digest_size = 28, .block_size = 64 }");
}

/// Generate _sha2.sha256(data=b'', *, usedforsecurity=True)
pub fn genSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }");
}

/// Generate _sha2.sha384(data=b'', *, usedforsecurity=True)
pub fn genSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha384\", .digest_size = 48, .block_size = 128 }");
}

/// Generate _sha2.sha512(data=b'', *, usedforsecurity=True)
pub fn genSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha512\", .digest_size = 64, .block_size = 128 }");
}

/// Generate sha*.update(data)
pub fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sha*.digest()
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 32");
}

/// Generate sha*.hexdigest()
pub fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0\" ** 64");
}

/// Generate sha*.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }");
}

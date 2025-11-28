/// Python _sha3 module - Internal SHA3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sha3.sha3_224(data=b'', *, usedforsecurity=True)
pub fn genSha3_224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_224\", .digest_size = 28, .block_size = 144 }");
}

/// Generate _sha3.sha3_256(data=b'', *, usedforsecurity=True)
pub fn genSha3_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }");
}

/// Generate _sha3.sha3_384(data=b'', *, usedforsecurity=True)
pub fn genSha3_384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_384\", .digest_size = 48, .block_size = 104 }");
}

/// Generate _sha3.sha3_512(data=b'', *, usedforsecurity=True)
pub fn genSha3_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_512\", .digest_size = 64, .block_size = 72 }");
}

/// Generate _sha3.shake_128(data=b'', *, usedforsecurity=True)
pub fn genShake128(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"shake_128\", .digest_size = 0, .block_size = 168 }");
}

/// Generate _sha3.shake_256(data=b'', *, usedforsecurity=True)
pub fn genShake256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"shake_256\", .digest_size = 0, .block_size = 136 }");
}

/// Generate sha3*.update(data)
pub fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sha3*.digest()
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\" ** 32");
}

/// Generate sha3*.hexdigest()
pub fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0\" ** 64");
}

/// Generate sha3*.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }");
}

/// Generate shake*.digest(length)
pub fn genShakeDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate shake*.hexdigest(length)
pub fn genShakeHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

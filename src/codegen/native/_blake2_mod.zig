/// Python _blake2 module - BLAKE2 hash functions (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _blake2.blake2b(data=b'', *, digest_size=64, key=b'', salt=b'', person=b'', fanout=1, depth=1, leaf_size=0, node_offset=0, node_depth=0, inner_size=0, last_node=False)
pub fn genBlake2b(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }");
}

/// Generate _blake2.blake2s(data=b'', *, digest_size=32, key=b'', salt=b'', person=b'', fanout=1, depth=1, leaf_size=0, node_offset=0, node_depth=0, inner_size=0, last_node=False)
pub fn genBlake2s(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"blake2s\", .digest_size = 32, .block_size = 64 }");
}

/// Generate blake2b.update(data)
pub fn genUpdate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate blake2b.digest()
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate blake2b.hexdigest()
pub fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0\" ** 128");
}

/// Generate blake2b.copy()
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }");
}

/// Generate _blake2.BLAKE2B_SALT_SIZE constant
pub fn genBlake2bSaltSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

/// Generate _blake2.BLAKE2B_PERSON_SIZE constant
pub fn genBlake2bPersonSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

/// Generate _blake2.BLAKE2B_MAX_KEY_SIZE constant
pub fn genBlake2bMaxKeySize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

/// Generate _blake2.BLAKE2B_MAX_DIGEST_SIZE constant
pub fn genBlake2bMaxDigestSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

/// Generate _blake2.BLAKE2S_SALT_SIZE constant
pub fn genBlake2sSaltSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8)");
}

/// Generate _blake2.BLAKE2S_PERSON_SIZE constant
pub fn genBlake2sPersonSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8)");
}

/// Generate _blake2.BLAKE2S_MAX_KEY_SIZE constant
pub fn genBlake2sMaxKeySize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 32)");
}

/// Generate _blake2.BLAKE2S_MAX_DIGEST_SIZE constant
pub fn genBlake2sMaxDigestSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 32)");
}

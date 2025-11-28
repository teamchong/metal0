/// Python _hashlib module - C accelerator for hashlib (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _hashlib.new(name, data=b'', **kwargs)
pub fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const name = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) 16 else if (std.mem.eql(u8, name, \"sha1\")) 20 else if (std.mem.eql(u8, name, \"sha256\")) 32 else if (std.mem.eql(u8, name, \"sha384\")) 48 else if (std.mem.eql(u8, name, \"sha512\")) 64 else 32 }; }");
    } else {
        try self.emit(".{ .name = \"sha256\", .digest_size = 32 }");
    }
}

/// Generate _hashlib.openssl_md5(data=b'')
pub fn genOpensslMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"md5\", .digest_size = 16 }");
}

/// Generate _hashlib.openssl_sha1(data=b'')
pub fn genOpensslSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha1\", .digest_size = 20 }");
}

/// Generate _hashlib.openssl_sha224(data=b'')
pub fn genOpensslSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha224\", .digest_size = 28 }");
}

/// Generate _hashlib.openssl_sha256(data=b'')
pub fn genOpensslSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha256\", .digest_size = 32 }");
}

/// Generate _hashlib.openssl_sha384(data=b'')
pub fn genOpensslSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha384\", .digest_size = 48 }");
}

/// Generate _hashlib.openssl_sha512(data=b'')
pub fn genOpensslSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha512\", .digest_size = 64 }");
}

/// Generate _hashlib.openssl_sha3_224(data=b'')
pub fn genOpensslSha3_224(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_224\", .digest_size = 28 }");
}

/// Generate _hashlib.openssl_sha3_256(data=b'')
pub fn genOpensslSha3_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_256\", .digest_size = 32 }");
}

/// Generate _hashlib.openssl_sha3_384(data=b'')
pub fn genOpensslSha3_384(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_384\", .digest_size = 48 }");
}

/// Generate _hashlib.openssl_sha3_512(data=b'')
pub fn genOpensslSha3_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"sha3_512\", .digest_size = 64 }");
}

/// Generate _hashlib.openssl_shake_128(data=b'')
pub fn genOpensslShake128(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"shake_128\", .digest_size = 0 }");
}

/// Generate _hashlib.openssl_shake_256(data=b'')
pub fn genOpensslShake256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"shake_256\", .digest_size = 0 }");
}

/// Generate _hashlib.pbkdf2_hmac(hash_name, password, salt, iterations, dklen=None)
pub fn genPbkdf2Hmac(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{} ** 32");
}

/// Generate _hashlib.scrypt(password, *, salt, n, r, p, maxmem=0, dklen=64)
pub fn genScrypt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{} ** 64");
}

/// Generate _hashlib.hmac_digest(key, msg, digest)
pub fn genHmacDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]u8{} ** 32");
}

/// Generate _hashlib.compare_digest(a, b)
pub fn genCompareDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.mem.eql(u8, ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("false");
    }
}

/// Generate _hashlib.openssl_md_meth_names
pub fn genOpensslMdMethNames(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }");
}

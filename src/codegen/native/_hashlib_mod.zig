/// Python _hashlib module - C accelerator for hashlib (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "new", genNew }, .{ "openssl_md5", genMd5 }, .{ "openssl_sha1", genSha1 },
    .{ "openssl_sha224", genSha224 }, .{ "openssl_sha256", genSha256 }, .{ "openssl_sha384", genSha384 }, .{ "openssl_sha512", genSha512 },
    .{ "openssl_sha3_224", genSha3_224 }, .{ "openssl_sha3_256", genSha3_256 }, .{ "openssl_sha3_384", genSha3_384 }, .{ "openssl_sha3_512", genSha3_512 },
    .{ "openssl_shake_128", genShake128 }, .{ "openssl_shake_256", genShake256 },
    .{ "pbkdf2_hmac", genBytes32 }, .{ "scrypt", genBytes64 }, .{ "hmac_digest", genBytes32 },
    .{ "compare_digest", genCompare }, .{ "openssl_md_meth_names", genNames },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"md5\", .digest_size = 16 }"); }
fn genSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha1\", .digest_size = 20 }"); }
fn genSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha224\", .digest_size = 28 }"); }
fn genSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha256\", .digest_size = 32 }"); }
fn genSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha384\", .digest_size = 48 }"); }
fn genSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha512\", .digest_size = 64 }"); }
fn genSha3_224(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_224\", .digest_size = 28 }"); }
fn genSha3_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_256\", .digest_size = 32 }"); }
fn genSha3_384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_384\", .digest_size = 48 }"); }
fn genSha3_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_512\", .digest_size = 64 }"); }
fn genShake128(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"shake_128\", .digest_size = 0 }"); }
fn genShake256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"shake_256\", .digest_size = 0 }"); }
fn genBytes32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{} ** 32"); }
fn genBytes64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{} ** 64"); }
fn genNames(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }"); }

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) 16 else if (std.mem.eql(u8, name, \"sha1\")) 20 else if (std.mem.eql(u8, name, \"sha256\")) 32 else if (std.mem.eql(u8, name, \"sha384\")) 48 else if (std.mem.eql(u8, name, \"sha512\")) 64 else 32 }; }"); } else { try self.emit(".{ .name = \"sha256\", .digest_size = 32 }"); }
}

fn genCompare(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.mem.eql(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); } else { try self.emit("false"); }
}

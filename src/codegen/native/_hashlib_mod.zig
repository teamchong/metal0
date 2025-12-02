/// Python _hashlib module - C accelerator for hashlib (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new", genNew }, .{ "openssl_md5", h.c(".{ .name = \"md5\", .digest_size = 16 }") }, .{ "openssl_sha1", h.c(".{ .name = \"sha1\", .digest_size = 20 }") },
    .{ "openssl_sha224", h.c(".{ .name = \"sha224\", .digest_size = 28 }") }, .{ "openssl_sha256", h.c(".{ .name = \"sha256\", .digest_size = 32 }") },
    .{ "openssl_sha384", h.c(".{ .name = \"sha384\", .digest_size = 48 }") }, .{ "openssl_sha512", h.c(".{ .name = \"sha512\", .digest_size = 64 }") },
    .{ "openssl_sha3_224", h.c(".{ .name = \"sha3_224\", .digest_size = 28 }") }, .{ "openssl_sha3_256", h.c(".{ .name = \"sha3_256\", .digest_size = 32 }") },
    .{ "openssl_sha3_384", h.c(".{ .name = \"sha3_384\", .digest_size = 48 }") }, .{ "openssl_sha3_512", h.c(".{ .name = \"sha3_512\", .digest_size = 64 }") },
    .{ "openssl_shake_128", h.c(".{ .name = \"shake_128\", .digest_size = 0 }") }, .{ "openssl_shake_256", h.c(".{ .name = \"shake_256\", .digest_size = 0 }") },
    .{ "pbkdf2_hmac", h.c("&[_]u8{} ** 32") }, .{ "scrypt", h.c("&[_]u8{} ** 64") }, .{ "hmac_digest", h.c("&[_]u8{} ** 32") },
    .{ "compare_digest", genCompare }, .{ "openssl_md_meth_names", h.c("&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }") },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) 16 else if (std.mem.eql(u8, name, \"sha1\")) 20 else if (std.mem.eql(u8, name, \"sha256\")) 32 else if (std.mem.eql(u8, name, \"sha384\")) 48 else if (std.mem.eql(u8, name, \"sha512\")) 64 else 32 }; }"); } else { try self.emit(".{ .name = \"sha256\", .digest_size = 32 }"); }
}

fn genCompare(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.mem.eql(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); } else { try self.emit("false"); }
}

/// Python _hashlib module - C accelerator for hashlib (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "new", genNew }, .{ "openssl_md5", genConst(".{ .name = \"md5\", .digest_size = 16 }") }, .{ "openssl_sha1", genConst(".{ .name = \"sha1\", .digest_size = 20 }") },
    .{ "openssl_sha224", genConst(".{ .name = \"sha224\", .digest_size = 28 }") }, .{ "openssl_sha256", genConst(".{ .name = \"sha256\", .digest_size = 32 }") },
    .{ "openssl_sha384", genConst(".{ .name = \"sha384\", .digest_size = 48 }") }, .{ "openssl_sha512", genConst(".{ .name = \"sha512\", .digest_size = 64 }") },
    .{ "openssl_sha3_224", genConst(".{ .name = \"sha3_224\", .digest_size = 28 }") }, .{ "openssl_sha3_256", genConst(".{ .name = \"sha3_256\", .digest_size = 32 }") },
    .{ "openssl_sha3_384", genConst(".{ .name = \"sha3_384\", .digest_size = 48 }") }, .{ "openssl_sha3_512", genConst(".{ .name = \"sha3_512\", .digest_size = 64 }") },
    .{ "openssl_shake_128", genConst(".{ .name = \"shake_128\", .digest_size = 0 }") }, .{ "openssl_shake_256", genConst(".{ .name = \"shake_256\", .digest_size = 0 }") },
    .{ "pbkdf2_hmac", genConst("&[_]u8{} ** 32") }, .{ "scrypt", genConst("&[_]u8{} ** 64") }, .{ "hmac_digest", genConst("&[_]u8{} ** 32") },
    .{ "compare_digest", genCompare }, .{ "openssl_md_meth_names", genConst("&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }") },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) 16 else if (std.mem.eql(u8, name, \"sha1\")) 20 else if (std.mem.eql(u8, name, \"sha256\")) 32 else if (std.mem.eql(u8, name, \"sha384\")) 48 else if (std.mem.eql(u8, name, \"sha512\")) 64 else 32 }; }"); } else { try self.emit(".{ .name = \"sha256\", .digest_size = 32 }"); }
}

fn genCompare(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.mem.eql(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); } else { try self.emit("false"); }
}

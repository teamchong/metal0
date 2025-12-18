/// Python _hashlib module - C accelerator for hashlib (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new", genNew },
    .{ "openssl_md5", genOpensslMd5 },
    .{ "openssl_sha1", genOpensslSha1 },
    .{ "openssl_sha224", genOpensslSha224 },
    .{ "openssl_sha256", genOpensslSha256 },
    .{ "openssl_sha384", genOpensslSha384 },
    .{ "openssl_sha512", genOpensslSha512 },
    .{ "openssl_sha3_224", genOpensslSha3_224 },
    .{ "openssl_sha3_256", genOpensslSha3_256 },
    .{ "openssl_sha3_384", genOpensslSha3_384 },
    .{ "openssl_sha3_512", genOpensslSha3_512 },
    .{ "openssl_shake_128", genOpensslShake128 },
    .{ "openssl_shake_256", genOpensslShake256 },
    .{ "pbkdf2_hmac", genPbkdf2Hmac },
    .{ "scrypt", genScrypt },
    .{ "hmac_digest", genHmacDigest },
    .{ "compare_digest", genCompareDigest },
    .{ "openssl_md_meth_names", genOpensslMdMethNames },
});

fn genNew(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha256\", .digest_size = 32 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("new");
    try self.emit("const name = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; break :{s} .{{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) @as(u8, 16) else if (std.mem.eql(u8, name, \"sha1\")) @as(u8, 20) else if (std.mem.eql(u8, name, \"sha256\")) @as(u8, 32) else if (std.mem.eql(u8, name, \"sha384\")) @as(u8, 48) else if (std.mem.eql(u8, name, \"sha512\")) @as(u8, 64) else @as(u8, 32) }}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genOpensslMd5(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"md5\", .digest_size = 16 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha1\", .digest_size = 20 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha224\", .digest_size = 28 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha256\", .digest_size = 32 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha384\", .digest_size = 48 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha512\", .digest_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha3_224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_224\", .digest_size = 28 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha3_256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_256\", .digest_size = 32 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha3_384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_384\", .digest_size = 48 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslSha3_512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_512\", .digest_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslShake128(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"shake_128\", .digest_size = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslShake256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"shake_256\", .digest_size = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genPbkdf2Hmac(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{} ** 32"), builder_mod.EmitConfig.forExpression());
}

fn genScrypt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{} ** 64"), builder_mod.EmitConfig.forExpression());
}

fn genHmacDigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{} ** 32"), builder_mod.EmitConfig.forExpression());
}

fn genCompareDigest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.emit("std.mem.eql(u8, ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
    }
}

fn genOpensslMdMethNames(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }"), builder_mod.EmitConfig.forExpression());
}

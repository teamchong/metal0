/// Python _hashlib module - C accelerator for hashlib (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
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
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write(".{ .name = \"sha256\", .digest_size = 32 }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("new", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const name = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; break :{s} .{{ .name = name, .digest_size = if (std.mem.eql(u8, name, \"md5\")) @as(u8, 16) else if (std.mem.eql(u8, name, \"sha1\")) @as(u8, 20) else if (std.mem.eql(u8, name, \"sha256\")) @as(u8, 32) else if (std.mem.eql(u8, name, \"sha384\")) @as(u8, 48) else if (std.mem.eql(u8, name, \"sha512\")) @as(u8, 64) else @as(u8, 32) }}", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genOpensslMd5(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"md5\", .digest_size = 16 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha1\", .digest_size = 20 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha224\", .digest_size = 28 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha256\", .digest_size = 32 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha384\", .digest_size = 48 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha512\", .digest_size = 64 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha3_224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha3_224\", .digest_size = 28 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha3_256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha3_256\", .digest_size = 32 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha3_384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha3_384\", .digest_size = 48 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslSha3_512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"sha3_512\", .digest_size = 64 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslShake128(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"shake_128\", .digest_size = 0 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genOpensslShake256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .name = \"shake_256\", .digest_size = 0 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genPbkdf2Hmac(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("&[_]u8{} ** 32");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genScrypt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("&[_]u8{} ** 64");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genHmacDigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("&[_]u8{} ** 32");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genCompareDigest(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 2) {
        {
            const b = try self.getBuilder();
            try b.write("std.mem.eql(u8, ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("false");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genOpensslMdMethNames(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("&[_][]const u8{ \"md5\", \"sha1\", \"sha224\", \"sha256\", \"sha384\", \"sha512\", \"sha3_224\", \"sha3_256\", \"sha3_384\", \"sha3_512\", \"shake_128\", \"shake_256\", \"blake2b\", \"blake2s\" }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

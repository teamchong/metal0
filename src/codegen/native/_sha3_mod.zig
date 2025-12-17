/// Python _sha3 module - Internal SHA3 support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sha3_224", genSha3_224 },
    .{ "sha3_256", genSha3_256 },
    .{ "sha3_384", genSha3_384 },
    .{ "sha3_512", genSha3_512 },
    .{ "shake128", genShake128 },
    .{ "shake256", genShake256 },
    .{ "update", genUpdate },
    .{ "digest", genDigest },
    .{ "hexdigest", genHexdigest },
    .{ "copy", genCopy },
    .{ "shake_digest", genShakeDigest },
    .{ "shake_hexdigest", genShakeHexdigest },
});

fn genSha3_224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_224\", .digest_size = 28, .block_size = 144 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha3_256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha3_384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_384\", .digest_size = 48, .block_size = 104 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha3_512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_512\", .digest_size = 64, .block_size = 72 }"), builder_mod.EmitConfig.forExpression());
}

fn genShake128(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"shake_128\", .digest_size = 0, .block_size = 168 }"), builder_mod.EmitConfig.forExpression());
}

fn genShake256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"shake_256\", .digest_size = 0, .block_size = 136 }"), builder_mod.EmitConfig.forExpression());
}

fn genUpdate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\x00\" ** 32"), builder_mod.EmitConfig.forExpression());
}

fn genHexdigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"0\" ** 64"), builder_mod.EmitConfig.forExpression());
}

fn genCopy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }"), builder_mod.EmitConfig.forExpression());
}

fn genShakeDigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genShakeHexdigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}


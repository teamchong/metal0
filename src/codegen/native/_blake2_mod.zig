/// Python _blake2 module - BLAKE2 hash functions (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "blake2b", genBlake2b },
    .{ "blake2s", genBlake2s },
    .{ "update", genUpdate },
    .{ "digest", genDigest },
    .{ "hexdigest", genHexdigest },
    .{ "copy", genCopy },
    .{ "BLAKE2B_SALT_SIZE", genBlake2bSaltSize },
    .{ "BLAKE2B_PERSON_SIZE", genBlake2bPersonSize },
    .{ "BLAKE2B_MAX_KEY_SIZE", genBlake2bMaxKeySize },
    .{ "BLAKE2B_MAX_DIGEST_SIZE", genBlake2bMaxDigestSize },
    .{ "BLAKE2S_SALT_SIZE", genBlake2sSaltSize },
    .{ "BLAKE2S_PERSON_SIZE", genBlake2sPersonSize },
    .{ "BLAKE2S_MAX_KEY_SIZE", genBlake2sMaxKeySize },
    .{ "BLAKE2S_MAX_DIGEST_SIZE", genBlake2sMaxDigestSize },
});

fn genBlake2b(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }"), builder_mod.EmitConfig.forExpression());
}

fn genBlake2s(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"blake2s\", .digest_size = 32, .block_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

fn genUpdate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genDigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genHexdigest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"0\" ** 128"), builder_mod.EmitConfig.forExpression());
}

fn genCopy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }"), builder_mod.EmitConfig.forExpression());
}

fn genBlake2bSaltSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genBlake2bPersonSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genBlake2bMaxKeySize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(64), builder_mod.EmitConfig.forExpression());
}

fn genBlake2bMaxDigestSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(64), builder_mod.EmitConfig.forExpression());
}

fn genBlake2sSaltSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genBlake2sPersonSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genBlake2sMaxKeySize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}

fn genBlake2sMaxDigestSize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}


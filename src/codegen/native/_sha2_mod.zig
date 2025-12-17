/// Python _sha2 module - Internal SHA2 support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sha224", genSha224 },
    .{ "sha256", genSha256 },
    .{ "sha384", genSha384 },
    .{ "sha512", genSha512 },
    .{ "update", genUpdate },
    .{ "digest", genDigest },
    .{ "hexdigest", genHexdigest },
    .{ "copy", genCopy },
});

fn genSha224(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha224\", .digest_size = 28, .block_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha384(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha384\", .digest_size = 48, .block_size = 128 }"), builder_mod.EmitConfig.forExpression());
}

fn genSha512(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha512\", .digest_size = 64, .block_size = 128 }"), builder_mod.EmitConfig.forExpression());
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
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }"), builder_mod.EmitConfig.forExpression());
}

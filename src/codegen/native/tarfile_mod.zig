/// Python tarfile module - Read and write tar archive files
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "is_tarfile", genIsTarfile },
    .{ "TarFile", genTarFile },
    .{ "TarInfo", genTarInfo },
    .{ "REGTYPE", genRegtype },
    .{ "AREGTYPE", genAregtype },
    .{ "LNKTYPE", genLnktype },
    .{ "SYMTYPE", genSymtype },
    .{ "CHRTYPE", genChrtype },
    .{ "BLKTYPE", genBlktype },
    .{ "DIRTYPE", genDirtype },
    .{ "FIFOTYPE", genFifotype },
    .{ "CONTTYPE", genConttype },
    .{ "GNUTYPE_LONGNAME", genGnutypeLongname },
    .{ "GNUTYPE_LONGLINK", genGnutypeLonglink },
    .{ "GNUTYPE_SPARSE", genGnutypeSparse },
    .{ "USTAR_FORMAT", genUstarFormat },
    .{ "GNU_FORMAT", genGnuFormat },
    .{ "PAX_FORMAT", genPaxFormat },
    .{ "DEFAULT_FORMAT", genDefaultFormat },
    .{ "BLOCKSIZE", genBlocksize },
    .{ "RECORDSIZE", genRecordsize },
    .{ "ENCODING", genEncoding },
});

fn genOpen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genIsTarfile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genTarFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genTarInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .size = @as(i64, 0), .mtime = @as(i64, 0), .mode = @as(i32, 0o644), .uid = @as(i32, 0), .gid = @as(i32, 0), .type = @as(u8, '0'), .linkname = \"\", .uname = \"\", .gname = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genRegtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '0')"), builder_mod.EmitConfig.forExpression());
}

fn genAregtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '\\x00')"), builder_mod.EmitConfig.forExpression());
}

fn genLnktype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '1')"), builder_mod.EmitConfig.forExpression());
}

fn genSymtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '2')"), builder_mod.EmitConfig.forExpression());
}

fn genChrtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '3')"), builder_mod.EmitConfig.forExpression());
}

fn genBlktype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '4')"), builder_mod.EmitConfig.forExpression());
}

fn genDirtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '5')"), builder_mod.EmitConfig.forExpression());
}

fn genFifotype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '6')"), builder_mod.EmitConfig.forExpression());
}

fn genConttype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, '7')"), builder_mod.EmitConfig.forExpression());
}

fn genGnutypeLongname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 'L')"), builder_mod.EmitConfig.forExpression());
}

fn genGnutypeLonglink(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 'K')"), builder_mod.EmitConfig.forExpression());
}

fn genGnutypeSparse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 'S')"), builder_mod.EmitConfig.forExpression());
}

fn genUstarFormat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGnuFormat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genPaxFormat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genDefaultFormat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genBlocksize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(512), builder_mod.EmitConfig.forExpression());
}

fn genRecordsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(10240), builder_mod.EmitConfig.forExpression());
}

fn genEncoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("utf-8"), builder_mod.EmitConfig.forExpression());
}

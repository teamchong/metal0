/// Python tarfile module - Read and write tar archive files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genTarInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\", .size = @as(i64, 0), .mtime = @as(i64, 0), .mode = @as(i32, 0o644), .uid = @as(i32, 0), .gid = @as(i32, 0), .type = @as(u8, '0'), .linkname = \"\", .uname = \"\", .gname = \"\" }"); }
fn genU8_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '0')"); }
fn genU8_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '1')"); }
fn genU8_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '2')"); }
fn genU8_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '3')"); }
fn genU8_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '4')"); }
fn genU8_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '5')"); }
fn genU8_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '6')"); }
fn genU8_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '7')"); }
fn genU8_Nul(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, '\\x00')"); }
fn genU8_L(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 'L')"); }
fn genU8_K(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 'K')"); }
fn genU8_S(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u8, 'S')"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 512)"); }
fn genI32_10240(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10240)"); }
fn genUtf8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"utf-8\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genNull }, .{ "is_tarfile", genFalse }, .{ "TarFile", genNull }, .{ "TarInfo", genTarInfo },
    .{ "REGTYPE", genU8_0 }, .{ "AREGTYPE", genU8_Nul }, .{ "LNKTYPE", genU8_1 }, .{ "SYMTYPE", genU8_2 },
    .{ "CHRTYPE", genU8_3 }, .{ "BLKTYPE", genU8_4 }, .{ "DIRTYPE", genU8_5 }, .{ "FIFOTYPE", genU8_6 }, .{ "CONTTYPE", genU8_7 },
    .{ "GNUTYPE_LONGNAME", genU8_L }, .{ "GNUTYPE_LONGLINK", genU8_K }, .{ "GNUTYPE_SPARSE", genU8_S },
    .{ "USTAR_FORMAT", genI32_0 }, .{ "GNU_FORMAT", genI32_1 }, .{ "PAX_FORMAT", genI32_2 }, .{ "DEFAULT_FORMAT", genI32_1 },
    .{ "BLOCKSIZE", genI32_512 }, .{ "RECORDSIZE", genI32_10240 }, .{ "ENCODING", genUtf8 },
});

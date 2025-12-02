/// Python tarfile module - Read and write tar archive files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genConst("@as(?*anyopaque, null)") }, .{ "is_tarfile", genConst("false") },
    .{ "TarFile", genConst("@as(?*anyopaque, null)") },
    .{ "TarInfo", genConst(".{ .name = \"\", .size = @as(i64, 0), .mtime = @as(i64, 0), .mode = @as(i32, 0o644), .uid = @as(i32, 0), .gid = @as(i32, 0), .type = @as(u8, '0'), .linkname = \"\", .uname = \"\", .gname = \"\" }") },
    .{ "REGTYPE", genConst("@as(u8, '0')") }, .{ "AREGTYPE", genConst("@as(u8, '\\x00')") },
    .{ "LNKTYPE", genConst("@as(u8, '1')") }, .{ "SYMTYPE", genConst("@as(u8, '2')") },
    .{ "CHRTYPE", genConst("@as(u8, '3')") }, .{ "BLKTYPE", genConst("@as(u8, '4')") },
    .{ "DIRTYPE", genConst("@as(u8, '5')") }, .{ "FIFOTYPE", genConst("@as(u8, '6')") },
    .{ "CONTTYPE", genConst("@as(u8, '7')") },
    .{ "GNUTYPE_LONGNAME", genConst("@as(u8, 'L')") }, .{ "GNUTYPE_LONGLINK", genConst("@as(u8, 'K')") },
    .{ "GNUTYPE_SPARSE", genConst("@as(u8, 'S')") },
    .{ "USTAR_FORMAT", genConst("@as(i32, 0)") }, .{ "GNU_FORMAT", genConst("@as(i32, 1)") },
    .{ "PAX_FORMAT", genConst("@as(i32, 2)") }, .{ "DEFAULT_FORMAT", genConst("@as(i32, 1)") },
    .{ "BLOCKSIZE", genConst("@as(i32, 512)") }, .{ "RECORDSIZE", genConst("@as(i32, 10240)") },
    .{ "ENCODING", genConst("\"utf-8\"") },
});

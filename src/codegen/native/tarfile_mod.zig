/// Python tarfile module - Read and write tar archive files
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "is_tarfile", h.c("false") },
    .{ "TarFile", h.c("@as(?*anyopaque, null)") },
    .{ "TarInfo", h.c(".{ .name = \"\", .size = @as(i64, 0), .mtime = @as(i64, 0), .mode = @as(i32, 0o644), .uid = @as(i32, 0), .gid = @as(i32, 0), .type = @as(u8, '0'), .linkname = \"\", .uname = \"\", .gname = \"\" }") },
    .{ "REGTYPE", h.c("@as(u8, '0')") }, .{ "AREGTYPE", h.c("@as(u8, '\\x00')") },
    .{ "LNKTYPE", h.c("@as(u8, '1')") }, .{ "SYMTYPE", h.c("@as(u8, '2')") },
    .{ "CHRTYPE", h.c("@as(u8, '3')") }, .{ "BLKTYPE", h.c("@as(u8, '4')") },
    .{ "DIRTYPE", h.c("@as(u8, '5')") }, .{ "FIFOTYPE", h.c("@as(u8, '6')") },
    .{ "CONTTYPE", h.c("@as(u8, '7')") },
    .{ "GNUTYPE_LONGNAME", h.c("@as(u8, 'L')") }, .{ "GNUTYPE_LONGLINK", h.c("@as(u8, 'K')") },
    .{ "GNUTYPE_SPARSE", h.c("@as(u8, 'S')") },
    .{ "USTAR_FORMAT", h.I32(0) }, .{ "GNU_FORMAT", h.I32(1) },
    .{ "PAX_FORMAT", h.I32(2) }, .{ "DEFAULT_FORMAT", h.I32(1) },
    .{ "BLOCKSIZE", h.I32(512) }, .{ "RECORDSIZE", h.I32(10240) },
    .{ "ENCODING", h.c("\"utf-8\"") },
});

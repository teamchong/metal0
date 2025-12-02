/// Python _stat module - Constants/functions from stat.h (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // File type constants
    .{ "S_IFMT", h.U32(0o170000) }, .{ "S_IFDIR", h.U32(0o040000) }, .{ "S_IFCHR", h.U32(0o020000) },
    .{ "S_IFBLK", h.U32(0o060000) }, .{ "S_IFREG", h.U32(0o100000) }, .{ "S_IFIFO", h.U32(0o010000) },
    .{ "S_IFLNK", h.U32(0o120000) }, .{ "S_IFSOCK", h.U32(0o140000) },
    // Permission bits
    .{ "S_ISUID", h.U32(0o4000) }, .{ "S_ISGID", h.U32(0o2000) }, .{ "S_ISVTX", h.U32(0o1000) },
    .{ "S_IRWXU", h.U32(0o700) }, .{ "S_IRUSR", h.U32(0o400) }, .{ "S_IWUSR", h.U32(0o200) }, .{ "S_IXUSR", h.U32(0o100) },
    .{ "S_IRWXG", h.U32(0o070) }, .{ "S_IRGRP", h.U32(0o040) }, .{ "S_IWGRP", h.U32(0o020) }, .{ "S_IXGRP", h.U32(0o010) },
    .{ "S_IRWXO", h.U32(0o007) }, .{ "S_IROTH", h.U32(0o004) }, .{ "S_IWOTH", h.U32(0o002) }, .{ "S_IXOTH", h.U32(0o001) },
    // Type test functions
    .{ "S_ISDIR", genTypeTest("0o040000") }, .{ "S_ISCHR", genTypeTest("0o020000") }, .{ "S_ISBLK", genTypeTest("0o060000") },
    .{ "S_ISREG", genTypeTest("0o100000") }, .{ "S_ISFIFO", genTypeTest("0o010000") }, .{ "S_ISLNK", genTypeTest("0o120000") }, .{ "S_ISSOCK", genTypeTest("0o140000") },
    .{ "S_IMODE", genS_IMODE }, .{ "filemode", genFilemode },
    // stat_result field indices
    .{ "ST_MODE", h.I32(0) }, .{ "ST_INO", h.I32(1) }, .{ "ST_DEV", h.I32(2) }, .{ "ST_NLINK", h.I32(3) },
    .{ "ST_UID", h.I32(4) }, .{ "ST_GID", h.I32(5) }, .{ "ST_SIZE", h.I32(6) },
    .{ "ST_ATIME", h.I32(7) }, .{ "ST_MTIME", h.I32(8) }, .{ "ST_CTIME", h.I32(9) },
    // Windows file attributes
    .{ "FILE_ATTRIBUTE_ARCHIVE", h.U32(32) }, .{ "FILE_ATTRIBUTE_COMPRESSED", h.U32(2048) },
    .{ "FILE_ATTRIBUTE_DEVICE", h.U32(64) }, .{ "FILE_ATTRIBUTE_DIRECTORY", h.U32(16) },
    .{ "FILE_ATTRIBUTE_ENCRYPTED", h.U32(16384) }, .{ "FILE_ATTRIBUTE_HIDDEN", h.U32(2) },
    .{ "FILE_ATTRIBUTE_NORMAL", h.U32(128) }, .{ "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED", h.U32(8192) },
    .{ "FILE_ATTRIBUTE_OFFLINE", h.U32(4096) }, .{ "FILE_ATTRIBUTE_READONLY", h.U32(1) },
    .{ "FILE_ATTRIBUTE_REPARSE_POINT", h.U32(1024) }, .{ "FILE_ATTRIBUTE_SPARSE_FILE", h.U32(512) },
    .{ "FILE_ATTRIBUTE_SYSTEM", h.U32(4) }, .{ "FILE_ATTRIBUTE_TEMPORARY", h.U32(256) },
    .{ "FILE_ATTRIBUTE_VIRTUAL", h.U32(65536) },
});

fn genTypeTest(comptime expected: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("(("); try self.genExpr(args[0]); try self.emit(" & 0o170000) == " ++ expected ++ ")"); } else try self.emit("false");
    } }.f;
}

fn genS_IMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" & 0o7777)"); } else try self.emit("@as(u32, 0)");
}

fn genFilemode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const mode = "); try self.genExpr(args[0]); try self.emit("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :blk &perm; }"); } else try self.emit("\"----------\"");
}

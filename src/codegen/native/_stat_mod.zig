/// Python _stat module - Constants/functions from stat.h (internal)
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c() factory for simple constant generators
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // File type constants - using h.c() factory
    .{ "S_IFMT", h.c("@as(u32, 0o170000)") },
    .{ "S_IFDIR", h.c("@as(u32, 0o040000)") },
    .{ "S_IFCHR", h.c("@as(u32, 0o020000)") },
    .{ "S_IFBLK", h.c("@as(u32, 0o060000)") },
    .{ "S_IFREG", h.c("@as(u32, 0o100000)") },
    .{ "S_IFIFO", h.c("@as(u32, 0o010000)") },
    .{ "S_IFLNK", h.c("@as(u32, 0o120000)") },
    .{ "S_IFSOCK", h.c("@as(u32, 0o140000)") },
    // Permission bits - using h.c() factory
    .{ "S_ISUID", h.c("@as(u32, 0o4000)") },
    .{ "S_ISGID", h.c("@as(u32, 0o2000)") },
    .{ "S_ISVTX", h.c("@as(u32, 0o1000)") },
    .{ "S_IRWXU", h.c("@as(u32, 0o700)") },
    .{ "S_IRUSR", h.c("@as(u32, 0o400)") },
    .{ "S_IWUSR", h.c("@as(u32, 0o200)") },
    .{ "S_IXUSR", h.c("@as(u32, 0o100)") },
    .{ "S_IRWXG", h.c("@as(u32, 0o070)") },
    .{ "S_IRGRP", h.c("@as(u32, 0o040)") },
    .{ "S_IWGRP", h.c("@as(u32, 0o020)") },
    .{ "S_IXGRP", h.c("@as(u32, 0o010)") },
    .{ "S_IRWXO", h.c("@as(u32, 0o007)") },
    .{ "S_IROTH", h.c("@as(u32, 0o004)") },
    .{ "S_IWOTH", h.c("@as(u32, 0o002)") },
    .{ "S_IXOTH", h.c("@as(u32, 0o001)") },
    // Type test functions - using h.modeCheck() factory
    .{ "S_ISDIR", h.modeCheck("0o040000") },
    .{ "S_ISCHR", h.modeCheck("0o020000") },
    .{ "S_ISBLK", h.modeCheck("0o060000") },
    .{ "S_ISREG", h.modeCheck("0o100000") },
    .{ "S_ISFIFO", h.modeCheck("0o010000") },
    .{ "S_ISLNK", h.modeCheck("0o120000") },
    .{ "S_ISSOCK", h.modeCheck("0o140000") },
    .{ "S_IMODE", genSIMODE },
    .{ "filemode", genFilemode },
    // stat_result field indices - using h.I32() factory
    .{ "ST_MODE", h.I32(0) },
    .{ "ST_INO", h.I32(1) },
    .{ "ST_DEV", h.I32(2) },
    .{ "ST_NLINK", h.I32(3) },
    .{ "ST_UID", h.I32(4) },
    .{ "ST_GID", h.I32(5) },
    .{ "ST_SIZE", h.I32(6) },
    .{ "ST_ATIME", h.I32(7) },
    .{ "ST_MTIME", h.I32(8) },
    .{ "ST_CTIME", h.I32(9) },
    // Windows file attributes - using h.c() factory
    .{ "FILE_ATTRIBUTE_ARCHIVE", h.c("@as(u32, 32)") },
    .{ "FILE_ATTRIBUTE_COMPRESSED", h.c("@as(u32, 2048)") },
    .{ "FILE_ATTRIBUTE_DEVICE", h.c("@as(u32, 64)") },
    .{ "FILE_ATTRIBUTE_DIRECTORY", h.c("@as(u32, 16)") },
    .{ "FILE_ATTRIBUTE_ENCRYPTED", h.c("@as(u32, 16384)") },
    .{ "FILE_ATTRIBUTE_HIDDEN", h.c("@as(u32, 2)") },
    .{ "FILE_ATTRIBUTE_NORMAL", h.c("@as(u32, 128)") },
    .{ "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED", h.c("@as(u32, 8192)") },
    .{ "FILE_ATTRIBUTE_OFFLINE", h.c("@as(u32, 4096)") },
    .{ "FILE_ATTRIBUTE_READONLY", h.c("@as(u32, 1)") },
    .{ "FILE_ATTRIBUTE_REPARSE_POINT", h.c("@as(u32, 1024)") },
    .{ "FILE_ATTRIBUTE_SPARSE_FILE", h.c("@as(u32, 512)") },
    .{ "FILE_ATTRIBUTE_SYSTEM", h.c("@as(u32, 4)") },
    .{ "FILE_ATTRIBUTE_TEMPORARY", h.c("@as(u32, 256)") },
    .{ "FILE_ATTRIBUTE_VIRTUAL", h.c("@as(u32, 65536)") },
});

// S_IMODE and filemode need special handling (different pattern)
fn genSIMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withParensCtx(args[0], struct {
            pub fn f(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                try s.genExpr(arg);
                try s.emit(" & 0o7777");
            }
        }.f);
    } else {
        try self.emit("@as(u32, 0)");
    }
}

fn genFilemode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"----------\"");
        return;
    }
    try self.withInlineBlock("fm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const mode = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :{s} &perm", .{label});
        }
    }.emit);
}

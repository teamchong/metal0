/// Python _stat module - Constants/functions from stat.h (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genOctal(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(u32, 0o{o})", .{n})); } }.f;
}
fn genU32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(u32, {})", .{n})); } }.f;
}
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // File type constants
    .{ "S_IFMT", genOctal(0o170000) }, .{ "S_IFDIR", genOctal(0o040000) }, .{ "S_IFCHR", genOctal(0o020000) },
    .{ "S_IFBLK", genOctal(0o060000) }, .{ "S_IFREG", genOctal(0o100000) }, .{ "S_IFIFO", genOctal(0o010000) },
    .{ "S_IFLNK", genOctal(0o120000) }, .{ "S_IFSOCK", genOctal(0o140000) },
    // Permission bits
    .{ "S_ISUID", genOctal(0o4000) }, .{ "S_ISGID", genOctal(0o2000) }, .{ "S_ISVTX", genOctal(0o1000) },
    .{ "S_IRWXU", genOctal(0o700) }, .{ "S_IRUSR", genOctal(0o400) }, .{ "S_IWUSR", genOctal(0o200) }, .{ "S_IXUSR", genOctal(0o100) },
    .{ "S_IRWXG", genOctal(0o070) }, .{ "S_IRGRP", genOctal(0o040) }, .{ "S_IWGRP", genOctal(0o020) }, .{ "S_IXGRP", genOctal(0o010) },
    .{ "S_IRWXO", genOctal(0o007) }, .{ "S_IROTH", genOctal(0o004) }, .{ "S_IWOTH", genOctal(0o002) }, .{ "S_IXOTH", genOctal(0o001) },
    // Type test functions
    .{ "S_ISDIR", genTypeTest(0o040000) }, .{ "S_ISCHR", genTypeTest(0o020000) }, .{ "S_ISBLK", genTypeTest(0o060000) },
    .{ "S_ISREG", genTypeTest(0o100000) }, .{ "S_ISFIFO", genTypeTest(0o010000) }, .{ "S_ISLNK", genTypeTest(0o120000) }, .{ "S_ISSOCK", genTypeTest(0o140000) },
    .{ "S_IMODE", genS_IMODE }, .{ "filemode", genFilemode },
    // stat_result field indices
    .{ "ST_MODE", genI32(0) }, .{ "ST_INO", genI32(1) }, .{ "ST_DEV", genI32(2) }, .{ "ST_NLINK", genI32(3) },
    .{ "ST_UID", genI32(4) }, .{ "ST_GID", genI32(5) }, .{ "ST_SIZE", genI32(6) },
    .{ "ST_ATIME", genI32(7) }, .{ "ST_MTIME", genI32(8) }, .{ "ST_CTIME", genI32(9) },
    // Windows file attributes
    .{ "FILE_ATTRIBUTE_ARCHIVE", genU32(32) }, .{ "FILE_ATTRIBUTE_COMPRESSED", genU32(2048) },
    .{ "FILE_ATTRIBUTE_DEVICE", genU32(64) }, .{ "FILE_ATTRIBUTE_DIRECTORY", genU32(16) },
    .{ "FILE_ATTRIBUTE_ENCRYPTED", genU32(16384) }, .{ "FILE_ATTRIBUTE_HIDDEN", genU32(2) },
    .{ "FILE_ATTRIBUTE_NORMAL", genU32(128) }, .{ "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED", genU32(8192) },
    .{ "FILE_ATTRIBUTE_OFFLINE", genU32(4096) }, .{ "FILE_ATTRIBUTE_READONLY", genU32(1) },
    .{ "FILE_ATTRIBUTE_REPARSE_POINT", genU32(1024) }, .{ "FILE_ATTRIBUTE_SPARSE_FILE", genU32(512) },
    .{ "FILE_ATTRIBUTE_SYSTEM", genU32(4) }, .{ "FILE_ATTRIBUTE_TEMPORARY", genU32(256) },
    .{ "FILE_ATTRIBUTE_VIRTUAL", genU32(65536) },
});

fn genTypeTest(comptime expected: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("(("); try self.genExpr(args[0]); try self.emit(std.fmt.comptimePrint(" & 0o170000) == 0o{o})", .{expected})); } else try self.emit("false");
    } }.f;
}
fn genS_IMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" & 0o7777)"); } else try self.emit("@as(u32, 0)");
}
fn genFilemode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const mode = "); try self.genExpr(args[0]); try self.emit("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :blk &perm; }"); } else try self.emit("\"----------\"");
}

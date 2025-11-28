/// Python _stat module - Constants/functions from stat.h (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// File type constants
pub fn genS_IFMT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o170000)");
}

pub fn genS_IFDIR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o040000)");
}

pub fn genS_IFCHR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o020000)");
}

pub fn genS_IFBLK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o060000)");
}

pub fn genS_IFREG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o100000)");
}

pub fn genS_IFIFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o010000)");
}

pub fn genS_IFLNK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o120000)");
}

pub fn genS_IFSOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o140000)");
}

// Permission bits
pub fn genS_ISUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o4000)");
}

pub fn genS_ISGID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o2000)");
}

pub fn genS_ISVTX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o1000)");
}

pub fn genS_IRWXU(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o700)");
}

pub fn genS_IRUSR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o400)");
}

pub fn genS_IWUSR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o200)");
}

pub fn genS_IXUSR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o100)");
}

pub fn genS_IRWXG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o070)");
}

pub fn genS_IRGRP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o040)");
}

pub fn genS_IWGRP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o020)");
}

pub fn genS_IXGRP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o010)");
}

pub fn genS_IRWXO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o007)");
}

pub fn genS_IROTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o004)");
}

pub fn genS_IWOTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o002)");
}

pub fn genS_IXOTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0o001)");
}

// Type test functions
pub fn genS_ISDIR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o040000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISCHR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o020000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISBLK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o060000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISREG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o100000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISFIFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o010000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISLNK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o120000)");
    } else {
        try self.emit("false");
    }
}

pub fn genS_ISSOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((");
        try self.genExpr(args[0]);
        try self.emit(" & 0o170000) == 0o140000)");
    } else {
        try self.emit("false");
    }
}

// Helper function - mode bits
pub fn genS_IMODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" & 0o7777)");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

pub fn genFilemode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const mode = ");
        try self.genExpr(args[0]);
        try self.emit("; var perm: [10]u8 = \"----------\".*; if ((mode & 0o170000) == 0o040000) perm[0] = 'd'; if ((mode & 0o400) != 0) perm[1] = 'r'; if ((mode & 0o200) != 0) perm[2] = 'w'; if ((mode & 0o100) != 0) perm[3] = 'x'; if ((mode & 0o040) != 0) perm[4] = 'r'; if ((mode & 0o020) != 0) perm[5] = 'w'; if ((mode & 0o010) != 0) perm[6] = 'x'; if ((mode & 0o004) != 0) perm[7] = 'r'; if ((mode & 0o002) != 0) perm[8] = 'w'; if ((mode & 0o001) != 0) perm[9] = 'x'; break :blk &perm; }");
    } else {
        try self.emit("\"----------\"");
    }
}

// stat_result field indices
pub fn genST_MODE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genST_INO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genST_DEV(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genST_NLINK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genST_UID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genST_GID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genST_SIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genST_ATIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genST_MTIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genST_CTIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

// File attribute flags (Windows)
pub fn genFILE_ATTRIBUTE_ARCHIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 32)");
}

pub fn genFILE_ATTRIBUTE_COMPRESSED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2048)");
}

pub fn genFILE_ATTRIBUTE_DEVICE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

pub fn genFILE_ATTRIBUTE_DIRECTORY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16)");
}

pub fn genFILE_ATTRIBUTE_ENCRYPTED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 16384)");
}

pub fn genFILE_ATTRIBUTE_HIDDEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2)");
}

pub fn genFILE_ATTRIBUTE_NORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 128)");
}

pub fn genFILE_ATTRIBUTE_NOT_CONTENT_INDEXED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 8192)");
}

pub fn genFILE_ATTRIBUTE_OFFLINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4096)");
}

pub fn genFILE_ATTRIBUTE_READONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1)");
}

pub fn genFILE_ATTRIBUTE_REPARSE_POINT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 1024)");
}

pub fn genFILE_ATTRIBUTE_SPARSE_FILE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 512)");
}

pub fn genFILE_ATTRIBUTE_SYSTEM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 4)");
}

pub fn genFILE_ATTRIBUTE_TEMPORARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 256)");
}

pub fn genFILE_ATTRIBUTE_VIRTUAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 65536)");
}

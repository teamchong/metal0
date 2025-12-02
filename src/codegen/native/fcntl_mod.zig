/// Python fcntl module - File control and I/O control operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fcntl", genZero }, .{ "ioctl", genZero }, .{ "flock", genUnit }, .{ "lockf", genUnit },
    .{ "F_DUPFD", genI32_0 }, .{ "F_GETFD", genI32_1 }, .{ "F_SETFD", genI32_2 },
    .{ "F_GETFL", genI32_3 }, .{ "F_SETFL", genI32_4 }, .{ "F_GETLK", genI32_5 },
    .{ "F_SETLK", genI32_6 }, .{ "F_SETLKW", genI32_7 },
    .{ "F_RDLCK", genI32_0 }, .{ "F_WRLCK", genI32_1 }, .{ "F_UNLCK", genI32_2 },
    .{ "FD_CLOEXEC", genI32_1 }, .{ "F_GETOWN", genI32_9 }, .{ "F_SETOWN", genI32_8 },
    .{ "F_GETSIG", genI32_11 }, .{ "F_SETSIG", genI32_10 },
    .{ "LOCK_SH", genI32_1 }, .{ "LOCK_EX", genI32_2 }, .{ "LOCK_NB", genI32_4 }, .{ "LOCK_UN", genI32_8 },
    .{ "F_LOCK", genI32_1 }, .{ "F_TLOCK", genI32_2 }, .{ "F_ULOCK", genI32_0 }, .{ "F_TEST", genI32_3 },
    .{ "O_RDONLY", genI32_0 }, .{ "O_WRONLY", genI32_1 }, .{ "O_RDWR", genI32_2 },
    .{ "O_CREAT", genO_CREAT }, .{ "O_EXCL", genO_EXCL }, .{ "O_NOCTTY", genO_NOCTTY },
    .{ "O_TRUNC", genO_TRUNC }, .{ "O_APPEND", genO_APPEND }, .{ "O_NONBLOCK", genO_NONBLOCK },
    .{ "O_DSYNC", genO_DSYNC }, .{ "O_SYNC", genO_SYNC }, .{ "O_ASYNC", genO_ASYNC },
    .{ "O_DIRECT", genO_DIRECT }, .{ "O_DIRECTORY", genO_DIRECTORY },
    .{ "O_NOFOLLOW", genO_NOFOLLOW }, .{ "O_CLOEXEC", genO_CLOEXEC },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 7)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genI32_10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genI32_11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 11)"); }

// Open flags (octal)
fn genO_CREAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o100)"); }
fn genO_EXCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o200)"); }
fn genO_NOCTTY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o400)"); }
fn genO_TRUNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o1000)"); }
fn genO_APPEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o2000)"); }
fn genO_NONBLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o4000)"); }
fn genO_DSYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o10000)"); }
fn genO_SYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o4010000)"); }
fn genO_ASYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o20000)"); }
fn genO_DIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o40000)"); }
fn genO_DIRECTORY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o200000)"); }
fn genO_NOFOLLOW(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o400000)"); }
fn genO_CLOEXEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0o2000000)"); }

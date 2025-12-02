/// Python fcntl module - File control and I/O control operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n})); }
fn genOctal(comptime v: []const u8) ModuleHandler { return genConst("@as(i32, " ++ v ++ ")"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fcntl", genConst("0") }, .{ "ioctl", genConst("0") }, .{ "flock", genConst("{}") }, .{ "lockf", genConst("{}") },
    .{ "F_DUPFD", genI32(0) }, .{ "F_GETFD", genI32(1) }, .{ "F_SETFD", genI32(2) },
    .{ "F_GETFL", genI32(3) }, .{ "F_SETFL", genI32(4) }, .{ "F_GETLK", genI32(5) },
    .{ "F_SETLK", genI32(6) }, .{ "F_SETLKW", genI32(7) },
    .{ "F_RDLCK", genI32(0) }, .{ "F_WRLCK", genI32(1) }, .{ "F_UNLCK", genI32(2) },
    .{ "FD_CLOEXEC", genI32(1) }, .{ "F_GETOWN", genI32(9) }, .{ "F_SETOWN", genI32(8) },
    .{ "F_GETSIG", genI32(11) }, .{ "F_SETSIG", genI32(10) },
    .{ "LOCK_SH", genI32(1) }, .{ "LOCK_EX", genI32(2) }, .{ "LOCK_NB", genI32(4) }, .{ "LOCK_UN", genI32(8) },
    .{ "F_LOCK", genI32(1) }, .{ "F_TLOCK", genI32(2) }, .{ "F_ULOCK", genI32(0) }, .{ "F_TEST", genI32(3) },
    .{ "O_RDONLY", genI32(0) }, .{ "O_WRONLY", genI32(1) }, .{ "O_RDWR", genI32(2) },
    .{ "O_CREAT", genOctal("0o100") }, .{ "O_EXCL", genOctal("0o200") }, .{ "O_NOCTTY", genOctal("0o400") },
    .{ "O_TRUNC", genOctal("0o1000") }, .{ "O_APPEND", genOctal("0o2000") }, .{ "O_NONBLOCK", genOctal("0o4000") },
    .{ "O_DSYNC", genOctal("0o10000") }, .{ "O_SYNC", genOctal("0o4010000") }, .{ "O_ASYNC", genOctal("0o20000") },
    .{ "O_DIRECT", genOctal("0o40000") }, .{ "O_DIRECTORY", genOctal("0o200000") },
    .{ "O_NOFOLLOW", genOctal("0o400000") }, .{ "O_CLOEXEC", genOctal("0o2000000") },
});

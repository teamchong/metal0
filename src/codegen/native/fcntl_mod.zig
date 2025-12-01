/// Python fcntl module - File control and I/O control operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "fcntl", genFcntl },
    .{ "ioctl", genIoctl },
    .{ "flock", genFlock },
    .{ "lockf", genLockf },
    .{ "F_DUPFD", genF_DUPFD },
    .{ "F_GETFD", genF_GETFD },
    .{ "F_SETFD", genF_SETFD },
    .{ "F_GETFL", genF_GETFL },
    .{ "F_SETFL", genF_SETFL },
    .{ "F_GETLK", genF_GETLK },
    .{ "F_SETLK", genF_SETLK },
    .{ "F_SETLKW", genF_SETLKW },
    .{ "F_RDLCK", genF_RDLCK },
    .{ "F_WRLCK", genF_WRLCK },
    .{ "F_UNLCK", genF_UNLCK },
    .{ "FD_CLOEXEC", genFD_CLOEXEC },
    .{ "F_GETOWN", genF_GETOWN },
    .{ "F_SETOWN", genF_SETOWN },
    .{ "F_GETSIG", genF_GETSIG },
    .{ "F_SETSIG", genF_SETSIG },
    .{ "LOCK_SH", genLOCK_SH },
    .{ "LOCK_EX", genLOCK_EX },
    .{ "LOCK_NB", genLOCK_NB },
    .{ "LOCK_UN", genLOCK_UN },
    .{ "F_LOCK", genF_LOCK },
    .{ "F_TLOCK", genF_TLOCK },
    .{ "F_ULOCK", genF_ULOCK },
    .{ "F_TEST", genF_TEST },
});

/// Generate fcntl.fcntl(fd, cmd, arg=0)
pub fn genFcntl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate fcntl.ioctl(fd, request, arg=0, mutate_flag=True)
pub fn genIoctl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate fcntl.flock(fd, operation)
pub fn genFlock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate fcntl.lockf(fd, cmd, len=0, start=0, whence=0)
pub fn genLockf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// fcntl constants
// ============================================================================

pub fn genF_DUPFD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genF_GETFD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genF_SETFD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genF_GETFL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genF_SETFL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genF_GETLK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genF_SETLK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genF_SETLKW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genF_RDLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genF_WRLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genF_UNLCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genFD_CLOEXEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genF_GETOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

pub fn genF_SETOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genF_GETSIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 11)");
}

pub fn genF_SETSIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

// ============================================================================
// flock constants
// ============================================================================

pub fn genLOCK_SH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genLOCK_EX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genLOCK_NB(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genLOCK_UN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

// ============================================================================
// lockf constants
// ============================================================================

pub fn genF_LOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genF_TLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genF_ULOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genF_TEST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

// ============================================================================
// open flags (duplicated from os module for convenience)
// ============================================================================

pub fn genO_RDONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genO_WRONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genO_RDWR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genO_CREAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o100)");
}

pub fn genO_EXCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o200)");
}

pub fn genO_NOCTTY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o400)");
}

pub fn genO_TRUNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o1000)");
}

pub fn genO_APPEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o2000)");
}

pub fn genO_NONBLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o4000)");
}

pub fn genO_DSYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o10000)");
}

pub fn genO_SYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o4010000)");
}

pub fn genO_ASYNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o20000)");
}

pub fn genO_DIRECT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o40000)");
}

pub fn genO_DIRECTORY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o200000)");
}

pub fn genO_NOFOLLOW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o400000)");
}

pub fn genO_CLOEXEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o2000000)");
}

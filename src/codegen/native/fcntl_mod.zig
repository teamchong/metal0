/// Python fcntl module - File control and I/O control operations
const std = @import("std");
const h = @import("mod_helper.zig");

fn genOctal(comptime v: []const u8) h.H { return h.c("@as(i32, " ++ v ++ ")"); }

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "fcntl", h.c("0") }, .{ "ioctl", h.c("0") }, .{ "flock", h.c("{}") }, .{ "lockf", h.c("{}") },
    .{ "F_DUPFD", h.I32(0) }, .{ "F_GETFD", h.I32(1) }, .{ "F_SETFD", h.I32(2) },
    .{ "F_GETFL", h.I32(3) }, .{ "F_SETFL", h.I32(4) }, .{ "F_GETLK", h.I32(5) },
    .{ "F_SETLK", h.I32(6) }, .{ "F_SETLKW", h.I32(7) },
    .{ "F_RDLCK", h.I32(0) }, .{ "F_WRLCK", h.I32(1) }, .{ "F_UNLCK", h.I32(2) },
    .{ "FD_CLOEXEC", h.I32(1) }, .{ "F_GETOWN", h.I32(9) }, .{ "F_SETOWN", h.I32(8) },
    .{ "F_GETSIG", h.I32(11) }, .{ "F_SETSIG", h.I32(10) },
    .{ "LOCK_SH", h.I32(1) }, .{ "LOCK_EX", h.I32(2) }, .{ "LOCK_NB", h.I32(4) }, .{ "LOCK_UN", h.I32(8) },
    .{ "F_LOCK", h.I32(1) }, .{ "F_TLOCK", h.I32(2) }, .{ "F_ULOCK", h.I32(0) }, .{ "F_TEST", h.I32(3) },
    .{ "O_RDONLY", h.I32(0) }, .{ "O_WRONLY", h.I32(1) }, .{ "O_RDWR", h.I32(2) },
    .{ "O_CREAT", genOctal("0o100") }, .{ "O_EXCL", genOctal("0o200") }, .{ "O_NOCTTY", genOctal("0o400") },
    .{ "O_TRUNC", genOctal("0o1000") }, .{ "O_APPEND", genOctal("0o2000") }, .{ "O_NONBLOCK", genOctal("0o4000") },
    .{ "O_DSYNC", genOctal("0o10000") }, .{ "O_SYNC", genOctal("0o4010000") }, .{ "O_ASYNC", genOctal("0o20000") },
    .{ "O_DIRECT", genOctal("0o40000") }, .{ "O_DIRECTORY", genOctal("0o200000") },
    .{ "O_NOFOLLOW", genOctal("0o400000") }, .{ "O_CLOEXEC", genOctal("0o2000000") },
});

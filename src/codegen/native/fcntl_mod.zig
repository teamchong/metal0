/// Python fcntl module - File control and I/O control operations
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I64() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions that return values
    .{ "fcntl", h.I64(0) },
    .{ "ioctl", h.I64(0) },
    .{ "flock", h.c("{}") },
    .{ "lockf", h.c("{}") },
    // F_* fcntl commands
    .{ "F_DUPFD", h.I64(0) },
    .{ "F_GETFD", h.I64(1) },
    .{ "F_SETFD", h.I64(2) },
    .{ "F_GETFL", h.I64(3) },
    .{ "F_SETFL", h.I64(4) },
    .{ "F_GETLK", h.I64(5) },
    .{ "F_SETLK", h.I64(6) },
    .{ "F_SETLKW", h.I64(7) },
    .{ "F_GETOWN", h.I64(9) },
    .{ "F_SETOWN", h.I64(8) },
    .{ "F_GETSIG", h.I64(11) },
    .{ "F_SETSIG", h.I64(10) },
    // F_*LCK lock types
    .{ "F_RDLCK", h.I64(0) },
    .{ "F_WRLCK", h.I64(1) },
    .{ "F_UNLCK", h.I64(2) },
    // FD_CLOEXEC flag
    .{ "FD_CLOEXEC", h.I64(1) },
    // LOCK_* flock operations
    .{ "LOCK_SH", h.I64(1) },
    .{ "LOCK_EX", h.I64(2) },
    .{ "LOCK_NB", h.I64(4) },
    .{ "LOCK_UN", h.I64(8) },
    // F_* lockf operations
    .{ "F_LOCK", h.I64(1) },
    .{ "F_TLOCK", h.I64(2) },
    .{ "F_ULOCK", h.I64(0) },
    .{ "F_TEST", h.I64(3) },
    // O_* open flags (basic)
    .{ "O_RDONLY", h.I64(0) },
    .{ "O_WRONLY", h.I64(1) },
    .{ "O_RDWR", h.I64(2) },
    // O_* open flags (octal)
    .{ "O_CREAT", h.c("@as(i32, 0o100)") },
    .{ "O_EXCL", h.c("@as(i32, 0o200)") },
    .{ "O_NOCTTY", h.c("@as(i32, 0o400)") },
    .{ "O_TRUNC", h.c("@as(i32, 0o1000)") },
    .{ "O_APPEND", h.c("@as(i32, 0o2000)") },
    .{ "O_NONBLOCK", h.c("@as(i32, 0o4000)") },
    .{ "O_DSYNC", h.c("@as(i32, 0o10000)") },
    .{ "O_SYNC", h.c("@as(i32, 0o4010000)") },
    .{ "O_ASYNC", h.c("@as(i32, 0o20000)") },
    .{ "O_DIRECT", h.c("@as(i32, 0o40000)") },
    .{ "O_DIRECTORY", h.c("@as(i32, 0o200000)") },
    .{ "O_NOFOLLOW", h.c("@as(i32, 0o400000)") },
    .{ "O_CLOEXEC", h.c("@as(i32, 0o2000000)") },
});

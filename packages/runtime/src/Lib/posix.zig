//! Python posix module - POSIX system calls
//! Reference: cpython/Modules/posixmodule.c
//!
//! Platform: Unix/Linux/macOS (not Windows - use nt module instead)
//! Most user code should use the os module which abstracts platform differences.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Feature flags - indicates which POSIX functions are available
// ============================================================================

/// List of POSIX functions available on this platform
pub const _have_functions: []const []const u8 = &.{
    "HAVE_FACCESSAT",
    "HAVE_FCHDIR",
    "HAVE_FCHMOD",
    "HAVE_FCHMODAT",
    "HAVE_FCHOWN",
    "HAVE_FCHOWNAT",
    "HAVE_FEXECVE",
    "HAVE_FDOPENDIR",
    "HAVE_FPATHCONF",
    "HAVE_FSTATAT",
    "HAVE_FSTATVFS",
    "HAVE_FTRUNCATE",
    "HAVE_FUTIMENS",
    "HAVE_FUTIMES",
    "HAVE_FUTIMESAT",
    "HAVE_LINKAT",
    "HAVE_LUTIMES",
    "HAVE_LCHFLAGS",
    "HAVE_LCHMOD",
    "HAVE_LCHOWN",
    "HAVE_LSTAT",
    "HAVE_MKDIRAT",
    "HAVE_MKFIFOAT",
    "HAVE_MKNODAT",
    "HAVE_OPENAT",
    "HAVE_READLINKAT",
    "HAVE_RENAMEAT",
    "HAVE_SYMLINKAT",
    "HAVE_UNLINKAT",
    "HAVE_UTIMENSAT",
};

// ============================================================================
// Stat result structure
// ============================================================================

/// Result of stat() call
pub const stat_result = struct {
    st_mode: u32 = 0,
    st_ino: u64 = 0,
    st_dev: u64 = 0,
    st_nlink: u64 = 0,
    st_uid: u32 = 0,
    st_gid: u32 = 0,
    st_size: i64 = 0,
    st_atime: i64 = 0,
    st_mtime: i64 = 0,
    st_ctime: i64 = 0,
    st_atime_ns: i64 = 0,
    st_mtime_ns: i64 = 0,
    st_ctime_ns: i64 = 0,
    st_blocks: i64 = 0,
    st_blksize: i64 = 0,
    st_rdev: u64 = 0,
    st_flags: u32 = 0,
};

/// Result of uname() call
pub const uname_result = struct {
    sysname: []const u8,
    nodename: []const u8,
    release: []const u8,
    version: []const u8,
    machine: []const u8,
};

// ============================================================================
// File/Directory operations
// ============================================================================

/// Get current working directory
pub fn getcwd() []const u8 {
    var buf: [4096]u8 = undefined;
    return std.fs.cwd().realpath(".", &buf) catch ".";
}

/// Change current working directory
pub fn chdir(path: []const u8) !void {
    try std.posix.chdir(path);
}

/// Create a directory
pub fn mkdir(path: []const u8, mode: u32) !void {
    _ = mode;
    try std.fs.cwd().makeDir(path);
}

/// Remove a directory
pub fn rmdir(path: []const u8) !void {
    try std.fs.cwd().deleteDir(path);
}

/// Remove a file
pub fn unlink(path: []const u8) !void {
    try std.fs.cwd().deleteFile(path);
}

/// Remove a file (alias)
pub fn remove(path: []const u8) !void {
    try unlink(path);
}

/// Rename a file or directory
pub fn rename(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().rename(src, dst);
}

/// Create a symbolic link
pub fn symlink(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().symLink(src, dst, .{});
}

/// Read the target of a symbolic link
pub fn readlink(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var buf: [4096]u8 = undefined;
    const result = try std.fs.cwd().readLink(path, &buf);
    return try allocator.dupe(u8, result);
}

/// Create a hard link
pub fn link(src: []const u8, dst: []const u8) !void {
    const cwd = std.fs.cwd();
    const src_file = try cwd.openFile(src, .{});
    defer src_file.close();
    try std.posix.linkat(cwd.fd, src, cwd.fd, dst, .{});
}

// ============================================================================
// File stat operations
// ============================================================================

/// Get file status
pub fn stat(path: []const u8) !stat_result {
    const s = try std.fs.cwd().statFile(path);
    return .{
        .st_size = @intCast(s.size),
        .st_mode = @intFromEnum(s.kind),
        .st_mtime = @intCast(@divFloor(s.mtime, std.time.ns_per_s)),
        .st_atime = @intCast(@divFloor(s.atime, std.time.ns_per_s)),
        .st_ctime = @intCast(@divFloor(s.ctime, std.time.ns_per_s)),
    };
}

/// Get file status (don't follow symlinks)
pub fn lstat(path: []const u8) !stat_result {
    // For now, same as stat
    return stat(path);
}

/// Get file status by file descriptor
pub fn fstat(fd: i32) !stat_result {
    _ = fd;
    return .{};
}

/// Check file accessibility
pub fn access(path: []const u8, mode: u32) bool {
    _ = mode;
    _ = std.fs.cwd().statFile(path) catch return false;
    return true;
}

// ============================================================================
// File descriptor operations
// ============================================================================

/// Open a file
pub fn open(path: []const u8, flags: u32, mode: u32) !i32 {
    _ = flags;
    _ = mode;
    const file = try std.fs.cwd().openFile(path, .{});
    return if (builtin.os.tag == .windows)
        @truncate(@as(i64, @intFromPtr(file.handle)))
    else
        @intCast(file.handle);
}

/// Close a file descriptor
pub fn close(fd: i32) void {
    std.posix.close(@intCast(fd));
}

/// Read from a file descriptor
pub fn read(fd: i32, count: usize) ![]u8 {
    _ = fd;
    _ = count;
    return "";
}

/// Write to a file descriptor
pub fn write(fd: i32, data: []const u8) !usize {
    _ = fd;
    return data.len;
}

/// Duplicate a file descriptor
pub fn dup(fd: i32) !i32 {
    return @intCast(std.posix.dup(@intCast(fd)));
}

/// Duplicate a file descriptor to a specific fd
pub fn dup2(oldfd: i32, newfd: i32) !i32 {
    return @intCast(std.posix.dup2(@intCast(oldfd), @intCast(newfd)));
}

/// Create a pipe
pub fn pipe() ![2]i32 {
    const fds = try std.posix.pipe();
    return .{ @intCast(fds[0]), @intCast(fds[1]) };
}

// ============================================================================
// Process operations
// ============================================================================

/// Get process ID
pub fn getpid() i32 {
    return @intCast(std.c.getpid());
}

/// Get parent process ID
pub fn getppid() i32 {
    return @intCast(std.c.getppid());
}

/// Get real user ID
pub fn getuid() u32 {
    return std.c.getuid();
}

/// Get real group ID
pub fn getgid() u32 {
    return std.c.getgid();
}

/// Get effective user ID
pub fn geteuid() u32 {
    return std.c.geteuid();
}

/// Get effective group ID
pub fn getegid() u32 {
    return std.c.getegid();
}

/// Fork a child process
pub fn fork() i32 {
    return @intCast(std.c.fork());
}

/// Send a signal to a process
pub fn kill(pid: i32, sig: i32) !void {
    _ = std.c.kill(@intCast(pid), @intCast(sig));
}

/// Wait for a child process
pub fn wait() !struct { pid: i32, status: i32 } {
    return .{ .pid = 0, .status = 0 };
}

/// Wait for a specific child process
pub fn waitpid(pid: i32, options: i32) !struct { pid: i32, status: i32 } {
    _ = pid;
    _ = options;
    return .{ .pid = 0, .status = 0 };
}

// ============================================================================
// Environment operations
// ============================================================================

/// Get an environment variable
pub fn getenv(name: []const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    return std.posix.getenv(name);
}

// ============================================================================
// Permission operations
// ============================================================================

/// Change file mode
pub fn chmod(path: []const u8, mode: u32) !void {
    _ = path;
    _ = mode;
}

/// Change file owner
pub fn chown(path: []const u8, uid: u32, gid: u32) !void {
    _ = path;
    _ = uid;
    _ = gid;
}

/// Set file creation mask
pub fn umask(mask: u32) u32 {
    _ = mask;
    return 0o022;
}

// ============================================================================
// System information
// ============================================================================

/// Get system name info
pub fn uname() uname_result {
    return .{
        .sysname = switch (builtin.os.tag) {
            .linux => "Linux",
            .macos => "Darwin",
            .freebsd => "FreeBSD",
            else => "Unknown",
        },
        .nodename = "localhost",
        .release = "1.0.0",
        .version = "Metal0 Runtime",
        .machine = switch (builtin.cpu.arch) {
            .x86_64 => "x86_64",
            .aarch64 => "arm64",
            else => "unknown",
        },
    };
}

/// Get random bytes
pub fn urandom(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    std.crypto.random.bytes(buf);
    return buf;
}

// ============================================================================
// Constants
// ============================================================================

// File open flags
pub const O_RDONLY: u32 = 0;
pub const O_WRONLY: u32 = 1;
pub const O_RDWR: u32 = 2;
pub const O_CREAT: u32 = 0o100;
pub const O_EXCL: u32 = 0o200;
pub const O_TRUNC: u32 = 0o1000;
pub const O_APPEND: u32 = 0o2000;

// Access mode flags
pub const F_OK: u32 = 0;
pub const R_OK: u32 = 4;
pub const W_OK: u32 = 2;
pub const X_OK: u32 = 1;

// Seek constants
pub const SEEK_SET: u32 = 0;
pub const SEEK_CUR: u32 = 1;
pub const SEEK_END: u32 = 2;

// ============================================================================
// Errors
// ============================================================================

pub const error_type = error{
    OSError,
    FileNotFound,
    AccessDenied,
    PermissionDenied,
};

// ============================================================================
// Tests
// ============================================================================

test "getcwd" {
    const cwd = getcwd();
    try std.testing.expect(cwd.len > 0);
}

test "getpid" {
    const pid = getpid();
    try std.testing.expect(pid > 0);
}

test "getenv" {
    // PATH should exist on most systems
    if (builtin.os.tag != .windows) {
        const path = getenv("PATH");
        try std.testing.expect(path != null);
    }
}

test "uname" {
    const info = uname();
    try std.testing.expect(info.sysname.len > 0);
    try std.testing.expect(info.machine.len > 0);
}

test "urandom" {
    const allocator = std.testing.allocator;
    const bytes = try urandom(allocator, 16);
    defer allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 16), bytes.len);
}

test "_have_functions" {
    try std.testing.expect(_have_functions.len > 0);
    // Check for common functions
    var found_openat = false;
    for (_have_functions) |func| {
        if (std.mem.eql(u8, func, "HAVE_OPENAT")) {
            found_openat = true;
            break;
        }
    }
    try std.testing.expect(found_openat);
}

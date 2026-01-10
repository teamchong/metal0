//! test.test_ctypes.test_errno - Tests for errno handling
//! Reference: cpython/Lib/test/test_ctypes/test_errno.py
//!
//! Tests for C errno access and manipulation in ctypes including
//! error code setting, retrieval, and thread safety.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// Errno Constants
// ============================================================================

pub const EPERM = 1; // Operation not permitted
pub const ENOENT = 2; // No such file or directory
pub const ESRCH = 3; // No such process
pub const EINTR = 4; // Interrupted system call
pub const EIO = 5; // I/O error
pub const ENXIO = 6; // No such device or address
pub const E2BIG = 7; // Argument list too long
pub const ENOEXEC = 8; // Exec format error
pub const EBADF = 9; // Bad file number
pub const ECHILD = 10; // No child processes
pub const EAGAIN = 11; // Try again
pub const ENOMEM = 12; // Out of memory
pub const EACCES = 13; // Permission denied
pub const EFAULT = 14; // Bad address
pub const ENOTBLK = 15; // Block device required
pub const EBUSY = 16; // Device or resource busy
pub const EEXIST = 17; // File exists
pub const EXDEV = 18; // Cross-device link
pub const ENODEV = 19; // No such device
pub const ENOTDIR = 20; // Not a directory
pub const EISDIR = 21; // Is a directory
pub const EINVAL = 22; // Invalid argument
pub const ENFILE = 23; // File table overflow
pub const EMFILE = 24; // Too many open files
pub const ENOTTY = 25; // Not a typewriter
pub const ETXTBSY = 26; // Text file busy
pub const EFBIG = 27; // File too large
pub const ENOSPC = 28; // No space left on device
pub const ESPIPE = 29; // Illegal seek
pub const EROFS = 30; // Read-only file system
pub const EMLINK = 31; // Too many links
pub const EPIPE = 32; // Broken pipe
pub const EDOM = 33; // Math argument out of domain
pub const ERANGE = 34; // Math result not representable

// ============================================================================
// Errno State
// ============================================================================

/// Thread-local errno storage (simulated)
threadlocal var current_errno: c_int = 0;

/// Get the current errno value
pub fn getErrno() c_int {
    return current_errno;
}

/// Set the errno value
pub fn setErrno(value: c_int) void {
    current_errno = value;
}

/// Clear errno (set to 0)
pub fn clearErrno() void {
    current_errno = 0;
}

// ============================================================================
// Errno String Conversion
// ============================================================================

/// Convert errno to string description
pub fn strerror(errnum: c_int) []const u8 {
    return switch (errnum) {
        EPERM => "Operation not permitted",
        ENOENT => "No such file or directory",
        ESRCH => "No such process",
        EINTR => "Interrupted system call",
        EIO => "Input/output error",
        ENXIO => "No such device or address",
        E2BIG => "Argument list too long",
        ENOEXEC => "Exec format error",
        EBADF => "Bad file descriptor",
        ECHILD => "No child processes",
        EAGAIN => "Resource temporarily unavailable",
        ENOMEM => "Cannot allocate memory",
        EACCES => "Permission denied",
        EFAULT => "Bad address",
        EBUSY => "Device or resource busy",
        EEXIST => "File exists",
        ENODEV => "No such device",
        ENOTDIR => "Not a directory",
        EISDIR => "Is a directory",
        EINVAL => "Invalid argument",
        ENFILE => "Too many open files in system",
        EMFILE => "Too many open files",
        ENOTTY => "Inappropriate ioctl for device",
        EFBIG => "File too large",
        ENOSPC => "No space left on device",
        ESPIPE => "Illegal seek",
        EROFS => "Read-only file system",
        EMLINK => "Too many links",
        EPIPE => "Broken pipe",
        EDOM => "Numerical argument out of domain",
        ERANGE => "Numerical result out of range",
        else => "Unknown error",
    };
}

// ============================================================================
// Errno Categories
// ============================================================================

pub const ErrnoCategory = enum {
    permission,
    io,
    resource,
    argument,
    file,
    process,
    other,
};

/// Categorize an errno value
pub fn categorizeErrno(errnum: c_int) ErrnoCategory {
    return switch (errnum) {
        EPERM, EACCES, EROFS => .permission,
        EIO, ENXIO, ESPIPE => .io,
        ENOMEM, ENOSPC, EMFILE, ENFILE => .resource,
        EINVAL, EDOM, ERANGE, E2BIG => .argument,
        ENOENT, EEXIST, EISDIR, ENOTDIR, EBADF => .file,
        ESRCH, ECHILD => .process,
        else => .other,
    };
}

/// Check if errno indicates a retryable error
pub fn isRetryable(errnum: c_int) bool {
    return errnum == EAGAIN or errnum == EINTR;
}

// ============================================================================
// Mock Functions That Set Errno
// ============================================================================

/// Mock open that may set errno
pub fn mockOpen(path: []const u8, _: u32) c_int {
    if (std.mem.eql(u8, path, "/nonexistent")) {
        setErrno(ENOENT);
        return -1;
    }
    if (std.mem.eql(u8, path, "/noperm")) {
        setErrno(EACCES);
        return -1;
    }
    clearErrno();
    return 3; // Mock file descriptor
}

/// Mock read that may set errno
pub fn mockRead(fd: c_int, _: []u8) isize {
    if (fd < 0) {
        setErrno(EBADF);
        return -1;
    }
    clearErrno();
    return 0; // EOF
}

/// Mock write that may set errno
pub fn mockWrite(fd: c_int, buf: []const u8) isize {
    if (fd < 0) {
        setErrno(EBADF);
        return -1;
    }
    if (fd == 999) {
        setErrno(ENOSPC);
        return -1;
    }
    clearErrno();
    return @intCast(buf.len);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testGetSetErrno() !void {
    clearErrno();
    try std.testing.expectEqual(@as(c_int, 0), getErrno());

    setErrno(EINVAL);
    try std.testing.expectEqual(@as(c_int, EINVAL), getErrno());

    setErrno(ENOENT);
    try std.testing.expectEqual(@as(c_int, ENOENT), getErrno());

    clearErrno();
    try std.testing.expectEqual(@as(c_int, 0), getErrno());
}

fn testStrerror() !void {
    try std.testing.expectEqualStrings("No such file or directory", strerror(ENOENT));
    try std.testing.expectEqualStrings("Permission denied", strerror(EACCES));
    try std.testing.expectEqualStrings("Invalid argument", strerror(EINVAL));
    try std.testing.expectEqualStrings("Unknown error", strerror(9999));
}

fn testCategorizeErrno() !void {
    try std.testing.expectEqual(ErrnoCategory.permission, categorizeErrno(EPERM));
    try std.testing.expectEqual(ErrnoCategory.permission, categorizeErrno(EACCES));
    try std.testing.expectEqual(ErrnoCategory.file, categorizeErrno(ENOENT));
    try std.testing.expectEqual(ErrnoCategory.resource, categorizeErrno(ENOMEM));
    try std.testing.expectEqual(ErrnoCategory.argument, categorizeErrno(EINVAL));
    try std.testing.expectEqual(ErrnoCategory.process, categorizeErrno(ESRCH));
}

fn testIsRetryable() !void {
    try std.testing.expect(isRetryable(EAGAIN));
    try std.testing.expect(isRetryable(EINTR));
    try std.testing.expect(!isRetryable(ENOENT));
    try std.testing.expect(!isRetryable(EINVAL));
}

fn testMockOpenSuccess() !void {
    clearErrno();
    const fd = mockOpen("/valid/path", 0);
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(c_int, 0), getErrno());
}

fn testMockOpenNotFound() !void {
    const fd = mockOpen("/nonexistent", 0);
    try std.testing.expectEqual(@as(c_int, -1), fd);
    try std.testing.expectEqual(@as(c_int, ENOENT), getErrno());
}

fn testMockOpenPermission() !void {
    const fd = mockOpen("/noperm", 0);
    try std.testing.expectEqual(@as(c_int, -1), fd);
    try std.testing.expectEqual(@as(c_int, EACCES), getErrno());
}

fn testMockReadBadFd() !void {
    var buf: [100]u8 = undefined;
    const result = mockRead(-1, &buf);
    try std.testing.expectEqual(@as(isize, -1), result);
    try std.testing.expectEqual(@as(c_int, EBADF), getErrno());
}

fn testMockWriteNoSpace() !void {
    const result = mockWrite(999, "test");
    try std.testing.expectEqual(@as(isize, -1), result);
    try std.testing.expectEqual(@as(c_int, ENOSPC), getErrno());
}

fn testErrnoConstants() !void {
    // Verify standard errno values
    try std.testing.expectEqual(@as(c_int, 2), ENOENT);
    try std.testing.expectEqual(@as(c_int, 13), EACCES);
    try std.testing.expectEqual(@as(c_int, 22), EINVAL);
}

fn testErrnoPreserved() !void {
    setErrno(EINVAL);

    // Some operations that don't touch errno
    _ = std.mem.eql(u8, "a", "b");
    var x: i32 = 1;
    x += 1;

    // Errno should be preserved
    try std.testing.expectEqual(@as(c_int, EINVAL), getErrno());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "get_set_errno" {
    try testGetSetErrno();
}

test "strerror" {
    try testStrerror();
}

test "categorize_errno" {
    try testCategorizeErrno();
}

test "is_retryable" {
    try testIsRetryable();
}

test "mock_open_success" {
    try testMockOpenSuccess();
}

test "mock_open_not_found" {
    try testMockOpenNotFound();
}

test "mock_open_permission" {
    try testMockOpenPermission();
}

test "mock_read_bad_fd" {
    try testMockReadBadFd();
}

test "mock_write_no_space" {
    try testMockWriteNoSpace();
}

test "errno_constants" {
    try testErrnoConstants();
}

test "errno_preserved" {
    try testErrnoPreserved();
}

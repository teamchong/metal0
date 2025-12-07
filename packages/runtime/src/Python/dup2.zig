/// dup2 - File Descriptor Duplication
/// Mirrors cpython/Python/dup2.c
///
/// This module provides file descriptor duplication for platforms
/// where dup2() is not natively available. Modern systems typically
/// have dup2, but this provides a fallback implementation.

const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

// ============================================================================
// Error Types
// ============================================================================

pub const Dup2Error = error{
    InvalidFileDescriptor,
    TooManyOpenFiles,
    SystemResources,
    Unexpected,
};

// ============================================================================
// Main Functions
// ============================================================================

/// Duplicate file descriptor to a specific number
/// Makes newfd a copy of oldfd, closing newfd first if necessary
pub fn dup2(oldfd: posix.fd_t, newfd: posix.fd_t) Dup2Error!posix.fd_t {
    // Validate file descriptors
    if (oldfd < 0 or newfd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    // If oldfd == newfd, just return (per POSIX spec)
    if (oldfd == newfd) {
        // Verify oldfd is valid by checking it
        _ = posix.fcntl(oldfd, .F_GETFD) catch {
            return Dup2Error.InvalidFileDescriptor;
        };
        return newfd;
    }

    // Use the system dup2
    const result = posix.dup2(oldfd, newfd) catch |err| {
        return switch (err) {
            error.FileDescriptorInvalid => Dup2Error.InvalidFileDescriptor,
            error.SystemResources => Dup2Error.SystemResources,
            else => Dup2Error.Unexpected,
        };
    };

    return result;
}

/// Duplicate file descriptor (get next available)
pub fn dup(oldfd: posix.fd_t) Dup2Error!posix.fd_t {
    if (oldfd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    const result = posix.dup(oldfd) catch |err| {
        return switch (err) {
            error.FileDescriptorInvalid => Dup2Error.InvalidFileDescriptor,
            error.SystemResources => Dup2Error.SystemResources,
            else => Dup2Error.Unexpected,
        };
    };

    return result;
}

/// Close a file descriptor
pub fn close(fd: posix.fd_t) void {
    if (fd >= 0) {
        posix.close(fd);
    }
}

// ============================================================================
// Python-style File Descriptor Operations
// ============================================================================

/// Duplicate fd to fd2, returning fd2 on success
/// This is the Python-compatible wrapper
pub fn py_dup2(fd: c_int, fd2: c_int) c_int {
    if (fd < 0 or fd2 < 0) {
        return -1;
    }

    const result = dup2(@intCast(fd), @intCast(fd2)) catch {
        return -1;
    };

    return @intCast(result);
}

/// Duplicate fd, returning new fd on success
pub fn py_dup(fd: c_int) c_int {
    if (fd < 0) {
        return -1;
    }

    const result = dup(@intCast(fd)) catch {
        return -1;
    };

    return @intCast(result);
}

// ============================================================================
// Atomic File Descriptor Operations
// ============================================================================

/// Atomically duplicate fd to a new descriptor >= minfd
pub fn dupCloexec(oldfd: posix.fd_t, minfd: posix.fd_t) Dup2Error!posix.fd_t {
    if (oldfd < 0 or minfd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    // Use F_DUPFD_CLOEXEC if available
    const result = posix.fcntl(oldfd, .F_DUPFD_CLOEXEC, @as(u32, @intCast(minfd))) catch |err| {
        return switch (err) {
            error.FileDescriptorInvalid => Dup2Error.InvalidFileDescriptor,
            error.SystemResources => Dup2Error.SystemResources,
            else => Dup2Error.Unexpected,
        };
    };

    return result;
}

/// Set close-on-exec flag for a file descriptor
pub fn setCloseOnExec(fd: posix.fd_t, cloexec: bool) Dup2Error!void {
    if (fd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    // Get current flags
    const flags = posix.fcntl(fd, .F_GETFD) catch {
        return Dup2Error.InvalidFileDescriptor;
    };

    // Set or clear FD_CLOEXEC
    const new_flags: u32 = if (cloexec)
        flags | posix.FD_CLOEXEC
    else
        flags & ~@as(u32, posix.FD_CLOEXEC);

    _ = posix.fcntl(fd, .F_SETFD, new_flags) catch {
        return Dup2Error.Unexpected;
    };
}

/// Check if fd has close-on-exec flag set
pub fn getCloseOnExec(fd: posix.fd_t) Dup2Error!bool {
    if (fd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    const flags = posix.fcntl(fd, .F_GETFD) catch {
        return Dup2Error.InvalidFileDescriptor;
    };

    return (flags & posix.FD_CLOEXEC) != 0;
}

// ============================================================================
// Non-Blocking Operations
// ============================================================================

/// Set non-blocking mode for a file descriptor
pub fn setNonBlocking(fd: posix.fd_t, nonblock: bool) Dup2Error!void {
    if (fd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    // Get current flags
    const flags = posix.fcntl(fd, .F_GETFL) catch {
        return Dup2Error.InvalidFileDescriptor;
    };

    // Set or clear O_NONBLOCK
    const new_flags: u32 = if (nonblock)
        flags | posix.O.NONBLOCK
    else
        flags & ~@as(u32, posix.O.NONBLOCK);

    _ = posix.fcntl(fd, .F_SETFL, new_flags) catch {
        return Dup2Error.Unexpected;
    };
}

/// Check if fd is in non-blocking mode
pub fn isNonBlocking(fd: posix.fd_t) Dup2Error!bool {
    if (fd < 0) {
        return Dup2Error.InvalidFileDescriptor;
    }

    const flags = posix.fcntl(fd, .F_GETFL) catch {
        return Dup2Error.InvalidFileDescriptor;
    };

    return (flags & posix.O.NONBLOCK) != 0;
}

// ============================================================================
// File Descriptor Validation
// ============================================================================

/// Check if a file descriptor is valid (open)
pub fn isValidFd(fd: posix.fd_t) bool {
    if (fd < 0) return false;

    _ = posix.fcntl(fd, .F_GETFD) catch {
        return false;
    };

    return true;
}

/// Get the maximum file descriptor number
pub fn getMaxFd() usize {
    // Use getrlimit to get RLIMIT_NOFILE
    const rlim = posix.getrlimit(.NOFILE);
    return @intCast(rlim.cur);
}

// ============================================================================
// Standard File Descriptors
// ============================================================================

pub const STDIN_FILENO: posix.fd_t = 0;
pub const STDOUT_FILENO: posix.fd_t = 1;
pub const STDERR_FILENO: posix.fd_t = 2;

/// Redirect standard streams
pub const StdRedirect = struct {
    saved_stdin: ?posix.fd_t = null,
    saved_stdout: ?posix.fd_t = null,
    saved_stderr: ?posix.fd_t = null,

    const Self = @This();

    /// Save current stdin and redirect to fd
    pub fn redirectStdin(self: *Self, fd: posix.fd_t) !void {
        if (self.saved_stdin == null) {
            self.saved_stdin = try dup(STDIN_FILENO);
        }
        _ = try dup2(fd, STDIN_FILENO);
    }

    /// Save current stdout and redirect to fd
    pub fn redirectStdout(self: *Self, fd: posix.fd_t) !void {
        if (self.saved_stdout == null) {
            self.saved_stdout = try dup(STDOUT_FILENO);
        }
        _ = try dup2(fd, STDOUT_FILENO);
    }

    /// Save current stderr and redirect to fd
    pub fn redirectStderr(self: *Self, fd: posix.fd_t) !void {
        if (self.saved_stderr == null) {
            self.saved_stderr = try dup(STDERR_FILENO);
        }
        _ = try dup2(fd, STDERR_FILENO);
    }

    /// Restore all saved streams
    pub fn restoreAll(self: *Self) void {
        if (self.saved_stdin) |fd| {
            _ = dup2(fd, STDIN_FILENO) catch {};
            close(fd);
            self.saved_stdin = null;
        }
        if (self.saved_stdout) |fd| {
            _ = dup2(fd, STDOUT_FILENO) catch {};
            close(fd);
            self.saved_stdout = null;
        }
        if (self.saved_stderr) |fd| {
            _ = dup2(fd, STDERR_FILENO) catch {};
            close(fd);
            self.saved_stderr = null;
        }
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "dup basic" {
    // Create a test file
    const file = try std.fs.cwd().createFile("test_dup.tmp", .{});
    defer std.fs.cwd().deleteFile("test_dup.tmp") catch {};
    const fd1 = file.handle;

    // Duplicate
    const fd2 = try dup(fd1);
    try std.testing.expect(fd2 >= 0);
    try std.testing.expect(fd2 != fd1);

    // Both should be valid
    try std.testing.expect(isValidFd(fd1));
    try std.testing.expect(isValidFd(fd2));

    close(fd2);
    file.close();
}

test "dup2 basic" {
    // Create test files
    const file1 = try std.fs.cwd().createFile("test_dup2_1.tmp", .{});
    defer std.fs.cwd().deleteFile("test_dup2_1.tmp") catch {};

    const file2 = try std.fs.cwd().createFile("test_dup2_2.tmp", .{});
    defer std.fs.cwd().deleteFile("test_dup2_2.tmp") catch {};

    const fd1 = file1.handle;
    const fd2 = file2.handle;

    // dup2 fd1 to fd2
    const result = try dup2(fd1, fd2);
    try std.testing.expectEqual(fd2, result);

    file1.close();
    close(fd2);
}

test "dup2 same fd" {
    const file = try std.fs.cwd().createFile("test_dup2_same.tmp", .{});
    defer std.fs.cwd().deleteFile("test_dup2_same.tmp") catch {};
    defer file.close();

    const fd = file.handle;

    // dup2 to same fd should succeed and return the fd
    const result = try dup2(fd, fd);
    try std.testing.expectEqual(fd, result);
}

test "isValidFd" {
    const file = try std.fs.cwd().createFile("test_valid_fd.tmp", .{});
    defer std.fs.cwd().deleteFile("test_valid_fd.tmp") catch {};
    const fd = file.handle;

    try std.testing.expect(isValidFd(fd));

    file.close();

    try std.testing.expect(!isValidFd(fd));
    try std.testing.expect(!isValidFd(-1));
}

test "py_dup" {
    const file = try std.fs.cwd().createFile("test_py_dup.tmp", .{});
    defer std.fs.cwd().deleteFile("test_py_dup.tmp") catch {};
    defer file.close();

    const fd1 = @as(c_int, @intCast(file.handle));
    const fd2 = py_dup(fd1);

    try std.testing.expect(fd2 >= 0);
    try std.testing.expect(fd2 != fd1);

    close(@intCast(fd2));
}

test "py_dup invalid" {
    const result = py_dup(-1);
    try std.testing.expectEqual(@as(c_int, -1), result);
}

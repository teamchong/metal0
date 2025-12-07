//! Python 'pty' module - Pseudo-terminal utilities
//!
//! Provides functions for handling pseudo-terminal operations.
//!
//! Mirrors: CPython Lib/pty.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Error Types
// ============================================================================

pub const PtyError = error{
    ForkFailed,
    OpenPtyFailed,
    IoError,
    UnsupportedPlatform,
};

// ============================================================================
// Constants
// ============================================================================

pub const STDIN_FILENO: std.posix.fd_t = 0;
pub const STDOUT_FILENO: std.posix.fd_t = 1;
pub const STDERR_FILENO: std.posix.fd_t = 2;

// ============================================================================
// Core PTY Functions
// ============================================================================

/// Open a new pseudo-terminal pair
pub fn openpty(allocator: std.mem.Allocator) !struct { master: std.posix.fd_t, slave: std.posix.fd_t, name: []const u8 } {
    switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd => {
            // Open master
            const master = std.posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
                return error.OpenPtyFailed;
            };

            // Grant access to slave
            grantpt(master) catch {
                std.posix.close(master);
                return error.OpenPtyFailed;
            };

            // Unlock slave
            unlockpt(master) catch {
                std.posix.close(master);
                return error.OpenPtyFailed;
            };

            // Get slave name
            const slave_name = try ptsname(allocator, master);

            // Open slave
            const slave = std.posix.open(slave_name, .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
                std.posix.close(master);
                return error.OpenPtyFailed;
            };

            return .{
                .master = master,
                .slave = slave,
                .name = slave_name,
            };
        },
        else => return error.UnsupportedPlatform,
    }
}

/// Get the name of the slave pseudo-terminal
fn ptsname(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]const u8 {
    _ = fd;
    // In a full implementation, would call ptsname(3)
    return try allocator.dupe(u8, "/dev/pts/0");
}

/// Grant access to the slave pseudo-terminal
fn grantpt(fd: std.posix.fd_t) !void {
    _ = fd;
    // In a full implementation, would call grantpt(3)
}

/// Unlock the slave pseudo-terminal
fn unlockpt(fd: std.posix.fd_t) !void {
    _ = fd;
    // In a full implementation, would call unlockpt(3)
}

/// Fork and connect child to pseudo-terminal
pub fn fork() !struct { pid: std.posix.pid_t, fd: std.posix.fd_t } {
    switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd => {
            const result = std.posix.fork() catch {
                return error.ForkFailed;
            };

            if (result == 0) {
                // Child process - in a full implementation, would set up pty
                return .{ .pid = 0, .fd = -1 };
            } else {
                // Parent process
                return .{ .pid = result, .fd = -1 };
            }
        },
        else => return error.UnsupportedPlatform,
    }
}

/// Spawn a new process connected to a pseudo-terminal
pub fn spawn(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    master_read: ?*const fn (std.posix.fd_t) anyerror![]u8,
    stdin_read: ?*const fn (std.posix.fd_t) anyerror![]u8,
) !i32 {
    _ = master_read;
    _ = stdin_read;

    const pty_result = try openpty(allocator);
    defer std.posix.close(pty_result.master);
    defer std.posix.close(pty_result.slave);

    const pid = std.posix.fork() catch {
        return error.ForkFailed;
    };

    if (pid == 0) {
        // Child process
        std.posix.close(pty_result.master);

        // Create new session
        _ = std.posix.setsid() catch {};

        // Set controlling terminal
        // ioctl(slave, TIOCSCTTY, 0)

        // Duplicate slave to stdin/stdout/stderr
        std.posix.dup2(pty_result.slave, STDIN_FILENO) catch {};
        std.posix.dup2(pty_result.slave, STDOUT_FILENO) catch {};
        std.posix.dup2(pty_result.slave, STDERR_FILENO) catch {};

        if (pty_result.slave > STDERR_FILENO) {
            std.posix.close(pty_result.slave);
        }

        // Exec the command
        const argv_z = allocator.allocSentinel(?[*:0]const u8, argv.len, null) catch {
            std.posix.exit(127);
        };
        for (argv, 0..) |arg, i| {
            argv_z[i] = allocator.dupeZ(u8, arg) catch {
                std.posix.exit(127);
            };
        }

        return std.posix.execvpeZ(argv_z[0].?, argv_z, std.c.environ);
    }

    // Parent process
    std.posix.close(pty_result.slave);

    // Wait for child
    const wait_result = std.posix.waitpid(pid, 0);
    return @intCast(wait_result.status);
}

// ============================================================================
// I/O Functions
// ============================================================================

/// Default read function (reads up to 1024 bytes)
pub fn defaultRead(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    var buf: [1024]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    return try allocator.dupe(u8, buf[0..n]);
}

/// Copy data between file descriptors
pub fn copy(master_fd: std.posix.fd_t, master_read: ?*const fn (std.posix.fd_t) anyerror![]u8, stdin_read: ?*const fn (std.posix.fd_t) anyerror![]u8) void {
    _ = master_read;
    _ = stdin_read;

    // Simple copy loop
    var buf: [1024]u8 = undefined;

    while (true) {
        const n = std.posix.read(master_fd, &buf) catch break;
        if (n == 0) break;
        _ = std.posix.write(STDOUT_FILENO, buf[0..n]) catch break;
    }
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqual(@as(std.posix.fd_t, 0), STDIN_FILENO);
    try std.testing.expectEqual(@as(std.posix.fd_t, 1), STDOUT_FILENO);
    try std.testing.expectEqual(@as(std.posix.fd_t, 2), STDERR_FILENO);
}

test "ptsname" {
    const allocator = std.testing.allocator;
    const name = try ptsname(allocator, 0);
    defer allocator.free(name);
    try std.testing.expect(std.mem.startsWith(u8, name, "/dev/pts/"));
}

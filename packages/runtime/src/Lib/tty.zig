//! CPython source: Lib/tty.py
//!
//! Provides functions for manipulating tty devices.
//!
//! Mirrors: CPython Lib/tty.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Terminal Modes
// ============================================================================

/// Input mode flags
pub const IFLAG = 0;
pub const OFLAG = 1;
pub const CFLAG = 2;
pub const LFLAG = 3;
pub const ISPEED = 4;
pub const OSPEED = 5;
pub const CC = 6;

// ============================================================================
// Error Types
// ============================================================================

pub const TtyError = error{
    NotATty,
    IoError,
    UnsupportedPlatform,
};

// ============================================================================
// Terminal Mode Handling
// ============================================================================

/// Terminal attributes storage
pub const Termios = struct {
    iflag: u32 = 0,
    oflag: u32 = 0,
    cflag: u32 = 0,
    lflag: u32 = 0,
    cc: [32]u8 = [_]u8{0} ** 32,
    ispeed: u32 = 0,
    ospeed: u32 = 0,
};

/// Get terminal attributes
pub fn tcgetattr(fd: std.posix.fd_t) !Termios {
    if (!std.posix.isatty(fd)) {
        return error.NotATty;
    }

    switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd => {
            var termios: std.posix.termios = undefined;
            const result = std.posix.tcgetattr(fd);
            if (result) |t| {
                return Termios{
                    .iflag = t.iflag,
                    .oflag = t.oflag,
                    .cflag = t.cflag,
                    .lflag = t.lflag,
                    .ispeed = @intFromEnum(t.ispeed),
                    .ospeed = @intFromEnum(t.ospeed),
                };
            } else |_| {
                return error.IoError;
            }
            _ = termios;
        },
        else => return error.UnsupportedPlatform,
    }
}

/// Set terminal attributes
pub fn tcsetattr(fd: std.posix.fd_t, when: std.posix.TCSA, attrs: Termios) !void {
    if (!std.posix.isatty(fd)) {
        return error.NotATty;
    }

    switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd => {
            var termios: std.posix.termios = .{
                .iflag = @bitCast(attrs.iflag),
                .oflag = @bitCast(attrs.oflag),
                .cflag = @bitCast(attrs.cflag),
                .lflag = @bitCast(attrs.lflag),
                .line = 0,
                .cc = undefined,
                .ispeed = @enumFromInt(attrs.ispeed),
                .ospeed = @enumFromInt(attrs.ospeed),
            };
            @memcpy(&termios.cc, attrs.cc[0..termios.cc.len]);

            std.posix.tcsetattr(fd, when, termios) catch {
                return error.IoError;
            };
        },
        else => return error.UnsupportedPlatform,
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Set terminal to raw mode
pub fn setraw(fd: std.posix.fd_t, when: ?std.posix.TCSA) !void {
    const actual_when = when orelse .FLUSH;

    var mode = try tcgetattr(fd);

    // Input flags - disable everything
    mode.iflag &= ~@as(u32, @bitCast(std.posix.tc_iflag_t{
        .BRKINT = true,
        .ICRNL = true,
        .INPCK = true,
        .ISTRIP = true,
        .IXON = true,
    }));

    // Output flags - disable post-processing
    mode.oflag &= ~@as(u32, @bitCast(std.posix.tc_oflag_t{
        .OPOST = true,
    }));

    // Control flags - set 8 bit chars
    mode.cflag &= ~@as(u32, @bitCast(std.posix.tc_cflag_t{
        .CSIZE = true,
        .PARENB = true,
    }));
    mode.cflag |= @as(u32, @bitCast(std.posix.tc_cflag_t{
        .CS8 = true,
    }));

    // Local flags - disable echoing, canonical mode, signals
    mode.lflag &= ~@as(u32, @bitCast(std.posix.tc_lflag_t{
        .ECHO = true,
        .ICANON = true,
        .IEXTEN = true,
        .ISIG = true,
    }));

    // Control chars - set read to return immediately
    mode.cc[std.posix.V.MIN] = 1;
    mode.cc[std.posix.V.TIME] = 0;

    try tcsetattr(fd, actual_when, mode);
}

/// Set terminal to cbreak mode
pub fn setcbreak(fd: std.posix.fd_t, when: ?std.posix.TCSA) !void {
    const actual_when = when orelse .FLUSH;

    var mode = try tcgetattr(fd);

    // Local flags - disable canonical mode but keep echo
    mode.lflag &= ~@as(u32, @bitCast(std.posix.tc_lflag_t{
        .ICANON = true,
    }));

    // Control chars - set read to return immediately
    mode.cc[std.posix.V.MIN] = 1;
    mode.cc[std.posix.V.TIME] = 0;

    try tcsetattr(fd, actual_when, mode);
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

test "Termios struct" {
    const attrs = Termios{};
    try std.testing.expectEqual(@as(u32, 0), attrs.iflag);
    try std.testing.expectEqual(@as(u32, 0), attrs.oflag);
}

test "constants" {
    try std.testing.expectEqual(@as(usize, 0), IFLAG);
    try std.testing.expectEqual(@as(usize, 3), LFLAG);
    try std.testing.expectEqual(@as(usize, 6), CC);
}

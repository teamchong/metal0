/// sys module - System-specific parameters and functions
const std = @import("std");
const builtin = @import("builtin");

/// Comptime platform detection (zero runtime cost)
pub const platform = switch (builtin.os.tag) {
    .macos => "darwin",
    .linux => "linux",
    .windows => "win32",
    else => "unknown",
};

/// Version info tuple (3, 12, 0)
pub const VersionInfo = struct {
    major: i32,
    minor: i32,
    micro: i32,
};

pub const version_info = VersionInfo{
    .major = 3,
    .minor = 12,
    .micro = 0,
};

/// Python version string (like "3.12.0 (pyaot)")
pub const version: []const u8 = "3.12.0 (PyAOT - Ahead-of-Time Compiled Python)";

/// Command-line arguments (set at startup)
pub var argv: [][]const u8 = &.{};

/// Exit the program with given code
pub fn exit(code: i32) noreturn {
    std.posix.exit(@intCast(code));
}

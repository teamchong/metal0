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

/// Python version string (like "3.12.0 (metal0)")
pub const version: []const u8 = "3.12.0 (metal0 - Ahead-of-Time Compiled Python)";

/// Command-line arguments (set at startup)
pub var argv: [][]const u8 = &.{};

/// Exit the program with given code
pub fn exit(code: i32) noreturn {
    std.posix.exit(@intCast(code));
}

/// Integer string conversion limit (0 = disabled, default = 4300)
/// This is a Python 3.11+ security feature to limit DoS attacks via huge int<->str conversions
var int_max_str_digits: i64 = 4300;

/// Get the current limit for integer string conversion
pub fn get_int_max_str_digits(_: std.mem.Allocator) !i64 {
    return int_max_str_digits;
}

/// Set the limit for integer string conversion (0 = disabled)
pub fn set_int_max_str_digits(_: std.mem.Allocator, n: i64) !i64 {
    int_max_str_digits = n;
    return n;
}

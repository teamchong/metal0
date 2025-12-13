/// Environment variable operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#os.environ
const std = @import("std");
const builtin = @import("builtin");

/// Get an environment variable
/// Note: std.posix.getenv unavailable on Windows (uses WTF-16)
pub fn getenv(key: [:0]const u8) ?[]const u8 {
    // Windows uses WTF-16 environment variables, not UTF-8
    // std.posix.getenv is unavailable on Windows
    if (comptime builtin.os.tag == .windows) return null;
    return std.posix.getenv(key);
}

/// Get environment variable with default
pub fn getenvDefault(key: [:0]const u8, default: []const u8) []const u8 {
    return getenv(key) orelse default;
}

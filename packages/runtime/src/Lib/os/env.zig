/// Environment variable operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#os.environ
const std = @import("std");

/// Get an environment variable
pub fn getenv(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

/// Get environment variable with default
pub fn getenvDefault(key: []const u8, default: []const u8) []const u8 {
    return getenv(key) orelse default;
}

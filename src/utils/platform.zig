/// Cross-platform utilities for POSIX/Windows compatibility
const std = @import("std");
const builtin = @import("builtin");

/// Cross-platform getenv - returns null on Windows (uses WTF-16, not supported)
/// On POSIX systems, returns the environment variable value as a UTF-8 string.
/// On Windows, returns null (Windows uses WTF-16 encoded environment variables).
pub fn getenv(key: [:0]const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        // Windows uses WTF-16 environment variables, not UTF-8
        // Return null - caller must handle Windows case separately if needed
        _ = key;
        return null;
    } else {
        return std.posix.getenv(key);
    }
}

/// Cross-platform getenv with compile-time key (convenience wrapper)
pub fn getenvZ(comptime key: [:0]const u8) ?[]const u8 {
    return getenv(key);
}

test "getenv returns null on unsupported platforms" {
    // On Windows this returns null, on POSIX it may return value or null
    const result = getenv("PATH");
    if (comptime builtin.os.tag == .windows) {
        try std.testing.expect(result == null);
    }
}

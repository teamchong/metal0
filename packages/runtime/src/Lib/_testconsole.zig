//! Windows Console Testing Module
//!
//! Platform-specific module - only available on Windows.
//! On non-Windows platforms, this module compiles but raises ModuleNotFoundError at runtime.
//!
//! CPython source: PC/_testconsole.c
//! CPython equivalent: Modules/_testconsole (Windows-only C extension for console testing)

const std = @import("std");
const builtin = @import("builtin");

// Compile-time platform check
const is_windows = builtin.os.tag == .windows;

/// Module initialization error
pub const ModuleError = error{
    PlatformNotSupported,
};

/// Check if this module is available on current platform
pub fn checkPlatform() ModuleError!void {
    if (!is_windows) {
        return error.PlatformNotSupported;
    }
}

/// Write input to console (used for testing console I/O)
/// Stub - raises error on non-Windows platforms
pub fn write_input(allocator: std.mem.Allocator, input: []const u8) !void {
    _ = allocator;
    _ = input;
    try checkPlatform();
    @panic("_testconsole.write_input not implemented for Windows yet");
}

/// Read output from console (used for testing console I/O)
/// Stub - raises error on non-Windows platforms
pub fn read_output(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    try checkPlatform();
    return error.PlatformNotSupported;
}

test "_testconsole platform check" {
    if (builtin.os.tag == .windows) {
        // Should succeed on Windows
        try checkPlatform();
    } else {
        // Should fail on non-Windows
        try std.testing.expectError(error.PlatformNotSupported, checkPlatform());
    }
}

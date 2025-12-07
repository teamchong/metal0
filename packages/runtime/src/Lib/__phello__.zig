/// __phello__ - Hello World Package Test Module
/// Mirrors cpython/Lib/__phello__/__init__.py
///
/// Package version of __hello__ for testing package imports.
/// This is a frozen test package in CPython.

const std = @import("std");

// ============================================================================
// Module Constants
// ============================================================================

/// The hello message (same as __hello__)
pub const MESSAGE: []const u8 = "Hello world!";

/// Package name
pub const __name__: []const u8 = "__phello__";

/// Package path (would be set by import system)
pub const __path__: []const []const u8 = &[_][]const u8{};

/// Module initialized flag
pub var initialized: bool = false;

// ============================================================================
// Submodules
// ============================================================================

/// Spam submodule simulation
pub const spam = struct {
    pub const MESSAGE: []const u8 = "Hello world!";

    pub fn getMessage() []const u8 {
        return MESSAGE;
    }
};

// ============================================================================
// Main Functions
// ============================================================================

/// Get the hello message
pub fn getMessage() []const u8 {
    return MESSAGE;
}

/// Print hello world message
pub fn main() void {
    std.debug.print("{s}\n", .{MESSAGE});
}

// ============================================================================
// Module Initialization
// ============================================================================

/// Initialize the module (called on import)
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "phello message" {
    try std.testing.expectEqualStrings("Hello world!", MESSAGE);
}

test "package name" {
    try std.testing.expectEqualStrings("__phello__", __name__);
}

test "spam submodule" {
    try std.testing.expectEqualStrings("Hello world!", spam.MESSAGE);
    try std.testing.expectEqualStrings("Hello world!", spam.getMessage());
}

test "get message" {
    const msg = getMessage();
    try std.testing.expectEqualStrings("Hello world!", msg);
}

test "initialization" {
    reset();
    try std.testing.expect(!initialized);
    init();
    try std.testing.expect(initialized);
    reset();
}

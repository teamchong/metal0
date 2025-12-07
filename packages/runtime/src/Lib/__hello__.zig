/// __hello__ - Hello World Test Module
/// Mirrors cpython/Lib/__hello__.py
///
/// Simple test module used for testing the import system.
/// Prints "Hello world!" when imported.

const std = @import("std");

// ============================================================================
// Module Constants
// ============================================================================

/// The hello message
pub const MESSAGE: []const u8 = "Hello world!";

/// Module initialized flag
pub var initialized: bool = false;

// ============================================================================
// Main Function
// ============================================================================

/// Print hello world message
pub fn main() void {
    std.debug.print("{s}\n", .{MESSAGE});
}

/// Get the hello message
pub fn getMessage() []const u8 {
    return MESSAGE;
}

// ============================================================================
// Module Initialization
// ============================================================================

/// Initialize the module (called on import)
pub fn init() void {
    if (initialized) return;
    initialized = true;
    // In CPython, this prints on import
    // We don't print by default to avoid side effects
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "hello message" {
    try std.testing.expectEqualStrings("Hello world!", MESSAGE);
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

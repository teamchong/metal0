//! __phello__.spam - Frozen test module (spam submodule)
//! Reference: cpython/Lib/__phello__/spam.py
//!
//! Test module for CPython's frozen import mechanism.
//! Part of the __phello__ (hello) test package.

const std = @import("std");

/// Module initialization flag
pub var initialized: bool = false;

/// Initialize the module
pub fn init() void {
    initialized = true;
}

/// Sample function
pub fn spam() []const u8 {
    return "spam";
}

/// Sample class-like function
pub fn Spam() type {
    return struct {
        const Self = @This();

        name: []const u8 = "Spam",

        pub fn hello(self: *const Self) []const u8 {
            _ = self;
            return "Hello from Spam!";
        }

        pub fn eggs(self: *const Self) []const u8 {
            _ = self;
            return "eggs";
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "spam function" {
    try std.testing.expectEqualStrings("spam", spam());
}

test "Spam type" {
    const s = Spam(){};
    try std.testing.expectEqualStrings("Hello from Spam!", s.hello());
    try std.testing.expectEqualStrings("eggs", s.eggs());
}

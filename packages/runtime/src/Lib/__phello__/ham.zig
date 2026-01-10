//! __phello__.ham - Frozen test module (ham subpackage)
//! Reference: cpython/Lib/__phello__/ham/__init__.py
//!
//! Test subpackage for CPython's frozen import mechanism.
//! Part of the __phello__ (hello) test package.

const std = @import("std");

// Re-export eggs submodule
pub const eggs = @import("ham/eggs.zig");

/// Module initialization flag
pub var initialized: bool = false;

/// Initialize the module
pub fn init() void {
    initialized = true;
}

/// Sample function
pub fn ham() []const u8 {
    return "ham";
}

/// Sample class-like function
pub fn Ham() type {
    return struct {
        const Self = @This();

        name: []const u8 = "Ham",

        pub fn hello(self: *const Self) []const u8 {
            _ = self;
            return "Hello from Ham!";
        }

        pub fn spam(self: *const Self) []const u8 {
            _ = self;
            return "spam";
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ham function" {
    try std.testing.expectEqualStrings("ham", ham());
}

test "Ham type" {
    const h = Ham(){};
    try std.testing.expectEqualStrings("Hello from Ham!", h.hello());
    try std.testing.expectEqualStrings("spam", h.spam());
}

//! __phello__.ham.eggs - Frozen test module (eggs submodule)
//! Reference: cpython/Lib/__phello__/ham/eggs.py
//!
//! Test submodule within the ham subpackage.
//! Part of the __phello__ (hello) test package hierarchy.

const std = @import("std");

/// Module initialization flag
pub var initialized: bool = false;

/// Initialize the module
pub fn init() void {
    initialized = true;
}

/// Sample function
pub fn eggs() []const u8 {
    return "eggs";
}

/// Sample class-like function
pub fn Eggs() type {
    return struct {
        const Self = @This();

        name: []const u8 = "Eggs",
        count: usize = 0,

        pub fn hello(self: *const Self) []const u8 {
            _ = self;
            return "Hello from Eggs!";
        }

        pub fn increment(self: *Self) void {
            self.count += 1;
        }

        pub fn getCount(self: *const Self) usize {
            return self.count;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "eggs function" {
    try std.testing.expectEqualStrings("eggs", eggs());
}

test "Eggs type" {
    var e = Eggs(){};
    try std.testing.expectEqualStrings("Hello from Eggs!", e.hello());
    try std.testing.expectEqual(@as(usize, 0), e.getCount());
    e.increment();
    try std.testing.expectEqual(@as(usize, 1), e.getCount());
}

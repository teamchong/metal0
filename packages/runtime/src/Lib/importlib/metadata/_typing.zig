//! importlib.metadata._typing - Type utilities
//! Reference: cpython/Lib/importlib/metadata/_typing.py

const std = @import("std");

/// Type alias for module specification
pub const ModuleSpec = @import("../../importlib.zig").ModuleSpec;

/// Type alias for loader
pub const Loader = @import("../../importlib.zig").Loader;

/// Optional type helper
pub fn Optional(comptime T: type) type {
    return ?T;
}

/// Union type helper
pub fn Union(comptime types: []const type) type {
    // In Zig, we use tagged unions - this is a placeholder
    _ = types;
    return *anyopaque;
}

/// TypeVar placeholder (no-op in Zig)
pub fn TypeVar(comptime name: []const u8) type {
    _ = name;
    return *anyopaque;
}

test "type helpers" {
    const OptInt = Optional(i32);
    const opt: OptInt = 42;
    try std.testing.expectEqual(@as(i32, 42), opt.?);
}

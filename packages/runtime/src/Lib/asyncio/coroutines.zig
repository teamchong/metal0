//! asyncio.coroutines - Coroutine type checking utilities
//! Reference: cpython/Lib/asyncio/coroutines.py
//!
//! CPython __all__: ('iscoroutine', 'iscoroutinefunction')

const std = @import("std");
const asyncio = @import("../asyncio.zig");

// Re-export type checking functions from asyncio.zig (DRY)
pub const iscoroutine = asyncio.iscoroutine;
pub const iscoroutinefunction = asyncio.iscoroutinefunction;
pub const isawaitable = asyncio.isawaitable;

/// Marker for coroutine wrapper (debug purposes)
pub const CoroutineWrapper = struct {
    func: *const fn () anyerror!void,
    name: []const u8,

    pub fn init(func: *const fn () anyerror!void, name: []const u8) CoroutineWrapper {
        return .{ .func = func, .name = name };
    }
};

// Tests
test "iscoroutinefunction" {
    const TestFn = fn () void;
    try std.testing.expect(iscoroutinefunction(TestFn));

    // Non-function types
    try std.testing.expect(!iscoroutinefunction(i64));
    try std.testing.expect(!iscoroutinefunction([]u8));
}

test "iscoroutine" {
    const AsyncFn = fn () anyerror!i64;
    try std.testing.expect(iscoroutine(AsyncFn));

    // Non-coroutine
    try std.testing.expect(!iscoroutine(i64));
}

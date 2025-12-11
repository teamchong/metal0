//! Helper functions for weak references
//!
//! Provides convenience functions for creating and inspecting weak references.

const std = @import("std");
const weakref_types = @import("types.zig");
const proxy_module = @import("proxy.zig");

const WeakRef = weakref_types.WeakRef;
const Proxy = proxy_module.Proxy;

// ============================================================================
// ref() - Create a weak reference
// ============================================================================

/// Create a weak reference to an object
pub fn ref(comptime T: type, obj: *T, callback: ?*const fn (?*T) void) WeakRef(T) {
    return WeakRef(T).init(obj, callback);
}

// ============================================================================
// proxy() - Create a proxy to an object
// ============================================================================

/// Create a proxy to a weakly-referenced object
pub fn proxy(comptime T: type, obj: *T) Proxy(T) {
    return Proxy(T).init(obj);
}

// ============================================================================
// getweakrefcount - Count weak references (simulated)
// ============================================================================

/// Get the number of weak references to an object
/// Note: In this implementation, always returns 0 or 1 since we don't
/// have a global registry
pub fn getweakrefcount(comptime T: type, obj: *T) usize {
    _ = obj;
    // Without a global registry, we can't count references
    return 0;
}

// ============================================================================
// getweakrefs - Get list of weak references (simulated)
// ============================================================================

/// Get list of weak references to an object
/// Note: Returns empty list since we don't have a global registry
pub fn getweakrefs(comptime T: type, allocator: std.mem.Allocator, obj: *T) ![]WeakRef(T) {
    _ = obj;
    return try allocator.alloc(WeakRef(T), 0);
}

// ============================================================================
// Tests
// ============================================================================

test "ref convenience function" {
    var value: i32 = 99;
    const weak = ref(i32, &value, null);

    try std.testing.expect(weak.alive());
    try std.testing.expectEqual(@as(i32, 99), weak.get().?.*);
}

test "proxy convenience function" {
    var value: i32 = 88;
    const p = proxy(i32, &value);

    try std.testing.expect(p.alive());
}

//! Proxy types for weak references
//!
//! Provides Proxy and CallableProxy implementations.

const std = @import("std");
const weakref_types = @import("types.zig");
const WeakRef = weakref_types.WeakRef;

// ============================================================================
// Proxy - Proxy to a weakly-referenced object
// ============================================================================

/// A proxy that forwards attribute access to a weakly-referenced object
pub fn Proxy(comptime T: type) type {
    return struct {
        const Self = @This();

        ref: WeakRef(T),

        pub fn init(obj: *T) Self {
            return .{
                .ref = WeakRef(T).init(obj, null),
            };
        }

        /// Get the underlying object (raises error if dead)
        pub fn get(self: Self) !*T {
            return self.ref.get() orelse error.ReferenceError;
        }

        /// Check if proxy is alive
        pub fn alive(self: Self) bool {
            return self.ref.alive();
        }
    };
}

// ============================================================================
// CallableProxyType
// ============================================================================

/// A callable proxy to a weakly-referenced callable
pub fn CallableProxy(comptime F: type) type {
    return struct {
        const Self = @This();

        ref: WeakRef(F),

        pub fn init(func: *F) Self {
            return .{
                .ref = WeakRef(F).init(func, null),
            };
        }

        /// Get the callable
        pub fn get(self: Self) !*F {
            return self.ref.get() orelse error.ReferenceError;
        }

        pub fn alive(self: Self) bool {
            return self.ref.alive();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "Proxy" {
    var value: i32 = 42;
    var p = Proxy(i32).init(&value);

    try std.testing.expect(p.alive());
    try std.testing.expectEqual(@as(*i32, &value), try p.get());
}

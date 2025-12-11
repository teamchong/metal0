//! Core weak reference types for weakref module
//!
//! Provides the fundamental WeakRef generic type and callback support.

const std = @import("std");

/// A weak reference wrapper that doesn't prevent garbage collection
/// Note: In Zig, we simulate weak refs since there's no GC. The reference
/// can be manually invalidated.
pub fn WeakRef(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T,
        callback: ?*const fn (?*T) void,

        /// Create a weak reference to an object
        pub fn init(obj: *T, callback: ?*const fn (?*T) void) Self {
            return .{
                .ptr = obj,
                .callback = callback,
            };
        }

        /// Get the referenced object, or null if it was collected
        pub fn get(self: Self) ?*T {
            return self.ptr;
        }

        /// Call the weak reference to get the object (Python's __call__)
        pub fn call(self: Self) ?*T {
            return self.get();
        }

        /// Check if the reference is still alive
        pub fn alive(self: Self) bool {
            return self.ptr != null;
        }

        /// Manually invalidate the reference (simulates collection)
        pub fn invalidate(self: *Self) void {
            if (self.callback) |cb| {
                cb(self.ptr);
            }
            self.ptr = null;
        }

        /// Get hash based on the referenced object's address
        pub fn hash(self: Self) u64 {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }

        /// Check equality with another weak reference
        pub fn eql(self: Self, other: Self) bool {
            return self.ptr == other.ptr;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WeakRef basic" {
    var value: i32 = 42;
    var weak = WeakRef(i32).init(&value, null);

    try std.testing.expect(weak.alive());
    try std.testing.expectEqual(@as(*i32, &value), weak.get().?);
    try std.testing.expectEqual(@as(i32, 42), weak.get().?.*);

    weak.invalidate();
    try std.testing.expect(!weak.alive());
    try std.testing.expect(weak.get() == null);
}

test "WeakRef callback" {
    var value: i32 = 42;

    const callback = struct {
        fn cb(_: ?*i32) void {
            // In real code, this would do cleanup
        }
    }.cb;

    var weak = WeakRef(i32).init(&value, callback);
    try std.testing.expect(weak.alive());
}

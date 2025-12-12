//! Weak reference set
//!
//! Provides WeakSet implementation.

const std = @import("std");
const weakref_types = @import("types.zig");
const WeakRef = weakref_types.WeakRef;

// ============================================================================
// WeakSet - Set with weak references
// ============================================================================

/// A set that holds weak references to its members
pub fn WeakSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const WeakT = WeakRef(T);

        allocator: std.mem.Allocator,
        items: std.ArrayList(WeakT),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        /// Add an item to the set
        pub fn add(self: *Self, item: *T) !void {
            // Check if already present
            for (self.items.items) |weak| {
                if (weak.ptr == item) {
                    return;
                }
            }
            try self.items.append(self.allocator, WeakRef(T).init(item, null));
        }

        /// Remove an item from the set
        pub fn remove(self: *Self, item: *T) bool {
            for (self.items.items, 0..) |weak, i| {
                if (weak.ptr == item) {
                    _ = self.items.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Discard an item (no error if not present)
        pub fn discard(self: *Self, item: *T) void {
            _ = self.remove(item);
        }

        /// Check if item is in set
        pub fn contains(self: Self, item: *T) bool {
            for (self.items.items) |weak| {
                if (weak.ptr == item and weak.alive()) {
                    return true;
                }
            }
            return false;
        }

        /// Remove dead references
        pub fn compact(self: *Self) void {
            var i: usize = 0;
            while (i < self.items.items.len) {
                if (!self.items.items[i].alive()) {
                    _ = self.items.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Number of alive items
        pub fn len(self: Self) usize {
            var count: usize = 0;
            for (self.items.items) |weak| {
                if (weak.alive()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WeakSet" {
    const allocator = std.testing.allocator;

    var item1: i32 = 1;
    var item2: i32 = 2;

    var set = WeakSet(i32).init(allocator);
    defer set.deinit();

    try set.add(&item1);
    try set.add(&item2);
    try set.add(&item1); // Duplicate, should not add

    try std.testing.expect(set.contains(&item1));
    try std.testing.expect(set.contains(&item2));
    try std.testing.expectEqual(@as(usize, 2), set.len());

    try std.testing.expect(set.remove(&item1));
    try std.testing.expect(!set.contains(&item1));
}

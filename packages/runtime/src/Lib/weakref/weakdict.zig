//! Weak reference dictionaries
//!
//! Provides WeakKeyDictionary and WeakValueDictionary implementations.

const std = @import("std");
const weakref_types = @import("types.zig");
const WeakRef = weakref_types.WeakRef;

// ============================================================================
// WeakKeyDictionary - Dictionary with weak keys
// ============================================================================

/// A dictionary that holds weak references to its keys
pub fn WeakKeyDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const WeakK = WeakRef(K);

        allocator: std.mem.Allocator,
        entries: std.ArrayList(Entry),

        const Entry = struct {
            key: WeakK,
            value: V,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entries = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.entries.deinit(self.allocator);
        }

        /// Set a value for a key (creates weak reference to key)
        pub fn put(self: *Self, key: *K, value: V) !void {
            // Check if key already exists
            for (self.entries.items) |*entry| {
                if (entry.key.ptr == key) {
                    entry.value = value;
                    return;
                }
            }
            // Add new entry
            try self.entries.append(self.allocator, .{
                .key = WeakRef(K).init(key, null),
                .value = value,
            });
        }

        /// Get a value by key
        pub fn get(self: Self, key: *K) ?V {
            for (self.entries.items) |entry| {
                if (entry.key.ptr == key) {
                    return entry.value;
                }
            }
            return null;
        }

        /// Remove a key
        pub fn remove(self: *Self, key: *K) bool {
            for (self.entries.items, 0..) |entry, i| {
                if (entry.key.ptr == key) {
                    _ = self.entries.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Remove all entries with dead references
        pub fn compact(self: *Self) void {
            var i: usize = 0;
            while (i < self.entries.items.len) {
                if (!self.entries.items[i].key.alive()) {
                    _ = self.entries.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Number of entries (including dead ones)
        pub fn len(self: Self) usize {
            return self.entries.items.len;
        }

        /// Number of alive entries
        pub fn aliveCount(self: Self) usize {
            var count: usize = 0;
            for (self.entries.items) |entry| {
                if (entry.key.alive()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

// ============================================================================
// WeakValueDictionary - Dictionary with weak values
// ============================================================================

/// A dictionary that holds weak references to its values
pub fn WeakValueDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const WeakV = WeakRef(V);

        allocator: std.mem.Allocator,
        entries: std.AutoHashMap(K, WeakV),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entries = std.AutoHashMap(K, WeakV).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entries.deinit();
        }

        /// Set a value (creates weak reference to value)
        pub fn put(self: *Self, key: K, value: *V) !void {
            try self.entries.put(key, WeakRef(V).init(value, null));
        }

        /// Get a value by key (returns null if dead)
        pub fn get(self: Self, key: K) ?*V {
            if (self.entries.get(key)) |weak_val| {
                return weak_val.get();
            }
            return null;
        }

        /// Remove a key
        pub fn remove(self: *Self, key: K) bool {
            return self.entries.remove(key);
        }

        /// Remove all entries with dead references
        pub fn compact(self: *Self) void {
            var to_remove: std.ArrayList(K) = .{};
            defer to_remove.deinit(self.allocator);

            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                if (!entry.value_ptr.alive()) {
                    to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
                }
            }

            for (to_remove.items) |key| {
                _ = self.entries.remove(key);
            }
        }

        /// Number of entries
        pub fn count(self: Self) usize {
            return self.entries.count();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WeakKeyDictionary" {
    const allocator = std.testing.allocator;

    var key1: i32 = 1;
    var key2: i32 = 2;

    var dict = WeakKeyDictionary(i32, []const u8).init(allocator);
    defer dict.deinit();

    try dict.put(&key1, "one");
    try dict.put(&key2, "two");

    try std.testing.expectEqualStrings("one", dict.get(&key1).?);
    try std.testing.expectEqualStrings("two", dict.get(&key2).?);
    try std.testing.expectEqual(@as(usize, 2), dict.len());

    try std.testing.expect(dict.remove(&key1));
    try std.testing.expect(dict.get(&key1) == null);
}

test "WeakValueDictionary" {
    const allocator = std.testing.allocator;

    var val1: i32 = 100;
    var val2: i32 = 200;

    var dict = WeakValueDictionary([]const u8, i32).init(allocator);
    defer dict.deinit();

    try dict.put("a", &val1);
    try dict.put("b", &val2);

    try std.testing.expectEqual(@as(*i32, &val1), dict.get("a").?);
    try std.testing.expectEqual(@as(*i32, &val2), dict.get("b").?);
}

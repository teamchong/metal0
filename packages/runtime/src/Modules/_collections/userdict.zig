/// UserDict - Wrapper around dict for easier subclassing
const std = @import("std");
const Allocator = std.mem.Allocator;

/// UserDict - A wrapper around dictionary objects for easier subclassing
pub fn UserDict(comptime K: type, comptime V: type) type {
    return struct {
        data: std.AutoHashMap(K, V),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .data = std.AutoHashMap(K, V).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: Self, key: K) ?V {
            return self.data.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            try self.data.put(key, value);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.data.remove(key);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.data.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.data.count();
        }

        pub fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        pub fn keys(self: Self) std.AutoHashMap(K, V).KeyIterator {
            return self.data.keyIterator();
        }

        pub fn values(self: Self) std.AutoHashMap(K, V).ValueIterator {
            return self.data.valueIterator();
        }

        pub fn iterator(self: Self) std.AutoHashMap(K, V).Iterator {
            return self.data.iterator();
        }

        /// Copy the UserDict
        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            var it = self.data.iterator();
            while (it.next()) |entry| {
                try new.data.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return new;
        }

        /// Update with entries from another map
        pub fn update(self: *Self, other: anytype) !void {
            var it = other.iterator();
            while (it.next()) |entry| {
                try self.data.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// Get with default value
        pub fn getOrDefault(self: Self, key: K, default: V) V {
            return self.data.get(key) orelse default;
        }

        /// setdefault - get or insert default
        pub fn setdefault(self: *Self, key: K, default: V) !V {
            const entry = try self.data.getOrPut(key);
            if (!entry.found_existing) {
                entry.value_ptr.* = default;
            }
            return entry.value_ptr.*;
        }

        /// pop - remove and return value
        pub fn pop(self: *Self, key: K, default: ?V) ?V {
            if (self.data.fetchSwapRemove(key)) |kv| {
                return kv.value;
            }
            return default;
        }

        /// popitem - remove and return arbitrary (key, value) pair
        pub fn popitem(self: *Self) ?struct { K, V } {
            var it = self.data.iterator();
            if (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                _ = self.data.remove(key);
                return .{ key, value };
            }
            return null;
        }
    };
}

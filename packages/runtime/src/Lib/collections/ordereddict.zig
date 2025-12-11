//! OrderedDict - Dict that remembers insertion order
//!
//! Mirrors: CPython Lib/collections/__init__.py - OrderedDict

const std = @import("std");

/// Dict that remembers insertion order
pub fn OrderedDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Entry = struct { key: K, value: V };

        allocator: std.mem.Allocator,
        map: std.AutoHashMap(K, usize), // Maps key to index in order
        order: std.ArrayList(Entry),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .map = std.AutoHashMap(K, usize).init(allocator),
                .order = std.ArrayList(Entry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.order.deinit();
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            if (self.map.get(key)) |idx| {
                self.order.items[idx].value = value;
            } else {
                try self.map.put(key, self.order.items.len);
                try self.order.append(.{ .key = key, .value = value });
            }
        }

        pub fn get(self: Self, key: K) ?V {
            if (self.map.get(key)) |idx| {
                return self.order.items[idx].value;
            }
            return null;
        }

        pub fn contains(self: Self, key: K) bool {
            return self.map.contains(key);
        }

        pub fn remove(self: *Self, key: K) bool {
            if (self.map.fetchSwapRemove(key)) |kv| {
                // Mark as removed (value becomes undefined)
                _ = kv;
                return true;
            }
            return false;
        }

        /// Get keys in insertion order
        pub fn keys(self: Self, allocator: std.mem.Allocator) ![]K {
            var result = try allocator.alloc(K, self.order.items.len);
            for (self.order.items, 0..) |entry, i| {
                result[i] = entry.key;
            }
            return result;
        }

        /// Get values in insertion order
        pub fn values(self: Self, allocator: std.mem.Allocator) ![]V {
            var result = try allocator.alloc(V, self.order.items.len);
            for (self.order.items, 0..) |entry, i| {
                result[i] = entry.value;
            }
            return result;
        }

        /// Move key to end
        pub fn moveToEnd(self: *Self, key: K) !void {
            if (self.map.get(key)) |idx| {
                const entry = self.order.items[idx];
                // Remove and re-add
                _ = self.order.orderedRemove(idx);

                // Update indices in map
                var iter = self.map.iterator();
                while (iter.next()) |kv| {
                    if (kv.value_ptr.* > idx) {
                        kv.value_ptr.* -= 1;
                    }
                }

                try self.order.append(entry);
                try self.map.put(key, self.order.items.len - 1);
            }
        }

        /// Pop item (LIFO by default)
        pub fn popitem(self: *Self, last: bool) !Entry {
            if (self.order.items.len == 0) return error.Empty;

            const idx = if (last) self.order.items.len - 1 else 0;
            const entry = self.order.items[idx];
            _ = self.map.remove(entry.key);
            _ = self.order.orderedRemove(idx);

            // Update indices
            if (!last) {
                var iter = self.map.iterator();
                while (iter.next()) |kv| {
                    if (kv.value_ptr.* > 0) {
                        kv.value_ptr.* -= 1;
                    }
                }
            }

            return entry;
        }

        pub fn len(self: Self) usize {
            return self.order.items.len;
        }

        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
            self.order.clearRetainingCapacity();
        }
    };
}

test "OrderedDict" {
    const allocator = std.testing.allocator;

    var od = OrderedDict(i32, []const u8).init(allocator);
    defer od.deinit();

    try od.put(1, "one");
    try od.put(2, "two");
    try od.put(3, "three");

    try std.testing.expectEqualStrings("two", od.get(2).?);

    const keys = try od.keys(allocator);
    defer allocator.free(keys);
    try std.testing.expectEqual(@as(usize, 3), keys.len);
}

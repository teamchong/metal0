/// OrderedDict - Dictionary that remembers insertion order
/// Note: In Python 3.7+, regular dict maintains order, but OrderedDict has
/// additional methods like move_to_end
const std = @import("std");
const Allocator = std.mem.Allocator;

/// OrderedDict() -> dict that remembers insertion order
pub fn OrderedDict(comptime K: type, comptime V: type) type {
    return struct {
        map: std.AutoHashMap(K, V),
        order: std.ArrayList(K),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .map = std.AutoHashMap(K, V).init(allocator),
                .order = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
            self.order.deinit(self.allocator);
        }

        /// Set value for key (maintains order)
        pub fn put(self: *Self, key: K, value: V) !void {
            const existed = self.map.contains(key);
            try self.map.put(key, value);
            if (!existed) {
                try self.order.append(self.allocator, key);
            }
        }

        /// Get value for key
        pub fn get(self: Self, key: K) ?V {
            return self.map.get(key);
        }

        /// Remove key
        pub fn remove(self: *Self, key: K) bool {
            if (!self.map.remove(key)) return false;
            // Remove from order list
            for (self.order.items, 0..) |k, i| {
                if (k == key) {
                    _ = self.order.orderedRemove(i);
                    break;
                }
            }
            return true;
        }

        /// Move key to end (or beginning if last=false)
        pub fn move_to_end(self: *Self, key: K, last: bool) !void {
            // Find and remove from current position
            var found_idx: ?usize = null;
            for (self.order.items, 0..) |k, i| {
                if (k == key) {
                    found_idx = i;
                    break;
                }
            }

            if (found_idx) |idx| {
                _ = self.order.orderedRemove(idx);
                if (last) {
                    try self.order.append(self.allocator, key);
                } else {
                    try self.order.insert(self.allocator, 0, key);
                }
            } else {
                return error.KeyError;
            }
        }

        /// Pop last (or first) item
        pub fn popitem(self: *Self, last: bool) !struct { K, V } {
            if (self.order.items.len == 0) return error.KeyError;

            const key = if (last)
                self.order.pop() orelse return error.KeyError
            else
                self.order.orderedRemove(0);

            const value = self.map.get(key) orelse return error.KeyError;
            _ = self.map.remove(key);

            return .{ key, value };
        }

        /// Get ordered keys
        pub fn keys(self: Self) []const K {
            return self.order.items;
        }

        /// Get number of items
        pub fn count(self: Self) usize {
            return self.map.count();
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
            self.order.clearRetainingCapacity();
        }

        /// __reversed__ - Return reversed iterator over keys
        pub fn reversed(self: Self) ReversedIterator {
            return ReversedIterator.init(self);
        }

        const ReversedIterator = struct {
            order_items: []const K,
            index: usize,

            fn init(od: OrderedDict(K, V)) ReversedIterator {
                return .{
                    .order_items = od.order.items,
                    .index = od.order.items.len,
                };
            }

            pub fn next(self: *ReversedIterator) ?K {
                if (self.index == 0) return null;
                self.index -= 1;
                return self.order_items[self.index];
            }
        };

        /// __eq__ - Compare two OrderedDicts for equality
        pub fn eql(self: Self, other: Self) bool {
            if (self.order.items.len != other.order.items.len) return false;

            for (self.order.items, 0..) |key, i| {
                if (other.order.items[i] != key) return false;
                const self_val = self.map.get(key);
                const other_val = other.map.get(key);
                if (self_val == null or other_val == null) return false;
                if (self_val.? != other_val.?) return false;
            }
            return true;
        }

        /// Copy the OrderedDict
        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            for (self.order.items) |key| {
                if (self.map.get(key)) |value| {
                    try new.put(key, value);
                }
            }
            return new;
        }

        /// setdefault - get or insert default
        pub fn setdefault(self: *Self, key: K, default: V) !V {
            if (self.map.get(key)) |v| {
                return v;
            }
            try self.put(key, default);
            return default;
        }

        /// values() - Return ordered values
        pub fn values(self: Self, allocator: Allocator) ![]V {
            var result = try allocator.alloc(V, self.order.items.len);
            for (self.order.items, 0..) |key, i| {
                result[i] = self.map.get(key) orelse continue;
            }
            return result;
        }

        /// items() - Return ordered key-value pairs
        pub fn items(self: Self, allocator: Allocator) ![]struct { key: K, value: V } {
            var result = try allocator.alloc(struct { key: K, value: V }, self.order.items.len);
            for (self.order.items, 0..) |key, i| {
                result[i] = .{ .key = key, .value = self.map.get(key) orelse continue };
            }
            return result;
        }

        /// contains / __contains__ - Check if key exists
        pub fn contains(self: Self, key: K) bool {
            return self.map.contains(key);
        }

        /// update(other) - Update with key-value pairs from another OrderedDict
        pub fn update(self: *Self, other: *const Self) !void {
            for (other.order.items) |key| {
                if (other.map.get(key)) |value| {
                    try self.put(key, value);
                }
            }
        }

        /// len() / __len__ - Return number of items
        pub fn len(self: Self) usize {
            return self.order.items.len;
        }

        /// pop(key) - Remove and return value for key
        pub fn pop(self: *Self, key: K) ?V {
            if (self.map.fetchSwapRemove(key)) |kv| {
                for (self.order.items, 0..) |k, i| {
                    if (k == key) {
                        _ = self.order.orderedRemove(i);
                        break;
                    }
                }
                return kv.value;
            }
            return null;
        }

        /// popWithDefault(key, default) - Remove and return value, or default if missing
        pub fn popWithDefault(self: *Self, key: K, default: V) V {
            return self.pop(key) orelse default;
        }

        /// getWithDefault(key, default) - Get value or default (without inserting)
        pub fn getWithDefault(self: Self, key: K, default: V) V {
            return self.map.get(key) orelse default;
        }

        /// fromkeys(keys, value) - Create OrderedDict from keys with same value
        pub fn fromkeys(allocator: Allocator, key_list: []const K, value: V) !Self {
            var od = Self.init(allocator);
            for (key_list) |key| {
                try od.put(key, value);
            }
            return od;
        }
    };
}

/// defaultdict - Dictionary with default factory
const std = @import("std");
const Allocator = std.mem.Allocator;

/// defaultdict([default_factory[, ...]]) -> dict with default factory
pub fn DefaultDict(comptime K: type, comptime V: type) type {
    return struct {
        map: std.AutoHashMap(K, V),
        default_factory: ?*const fn () V,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .map = std.AutoHashMap(K, V).init(allocator),
                .default_factory = null,
                .allocator = allocator,
            };
        }

        pub fn initWithFactory(allocator: Allocator, factory: *const fn () V) Self {
            return .{
                .map = std.AutoHashMap(K, V).init(allocator),
                .default_factory = factory,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        /// Get value for key, creating default if missing
        pub fn get(self: *Self, key: K) !V {
            if (self.map.get(key)) |v| {
                return v;
            }

            if (self.default_factory) |factory| {
                const default = factory();
                try self.map.put(key, default);
                return default;
            }

            return error.KeyError;
        }

        /// Get value without creating default
        pub fn getExisting(self: Self, key: K) ?V {
            return self.map.get(key);
        }

        /// Set value for key
        pub fn put(self: *Self, key: K, value: V) !void {
            try self.map.put(key, value);
        }

        /// Remove key
        pub fn remove(self: *Self, key: K) bool {
            return self.map.remove(key);
        }

        /// Check if key exists
        pub fn contains(self: Self, key: K) bool {
            return self.map.contains(key);
        }

        /// Get number of items
        pub fn count(self: Self) usize {
            return self.map.count();
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
        }

        /// Iterator over keys
        pub fn keys(self: Self) std.AutoHashMap(K, V).KeyIterator {
            return self.map.keyIterator();
        }

        /// Iterator over values
        pub fn values(self: Self) std.AutoHashMap(K, V).ValueIterator {
            return self.map.valueIterator();
        }

        /// Iterator over key-value pairs
        pub fn items(self: *Self) std.AutoHashMap(K, V).Iterator {
            return self.map.iterator();
        }

        /// Get value with default fallback (without creating entry)
        pub fn getWithDefault(self: Self, key: K, default: V) V {
            return self.map.get(key) orelse default;
        }

        /// setdefault(key, default) - Get value, or set and return default if missing
        pub fn setdefault(self: *Self, key: K, default: V) !V {
            if (self.map.get(key)) |v| {
                return v;
            }
            try self.map.put(key, default);
            return default;
        }

        /// pop(key) - Remove and return value for key
        pub fn pop(self: *Self, key: K) ?V {
            if (self.map.fetchSwapRemove(key)) |kv| {
                return kv.value;
            }
            return null;
        }

        /// popWithDefault(key, default) - Remove and return value, or default if missing
        pub fn popWithDefault(self: *Self, key: K, default: V) V {
            if (self.map.fetchSwapRemove(key)) |kv| {
                return kv.value;
            }
            return default;
        }

        /// update(other) - Update with key-value pairs from another map
        pub fn update(self: *Self, other: *const std.AutoHashMap(K, V)) !void {
            var it = other.iterator();
            while (it.next()) |entry| {
                try self.map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// copy() - Return a shallow copy
        pub fn copyDict(self: Self) !Self {
            var new = Self.init(self.allocator);
            var it = self.map.iterator();
            while (it.next()) |entry| {
                try new.map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            new.default_factory = self.default_factory;
            return new;
        }

        /// __len__ / len()
        pub fn len(self: Self) usize {
            return self.map.count();
        }
    };
}

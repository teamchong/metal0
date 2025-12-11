/// ChainMap - Dict-like class for creating a single view of multiple mappings
const std = @import("std");
const Allocator = std.mem.Allocator;

/// ChainMap(*maps) -> ChainMap that groups multiple dicts together
/// Lookups search the underlying mappings successively until a key is found
pub fn ChainMap(comptime K: type, comptime V: type) type {
    return struct {
        maps: std.ArrayList(*std.AutoHashMap(K, V)),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .maps = std.ArrayList(*std.AutoHashMap(K, V)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.maps.deinit();
        }

        /// Add a new mapping at the front
        pub fn addMap(self: *Self, map: *std.AutoHashMap(K, V)) !void {
            try self.maps.insert(0, map);
        }

        /// Get value from first map that contains key
        pub fn get(self: Self, key: K) ?V {
            for (self.maps.items) |map| {
                if (map.get(key)) |v| return v;
            }
            return null;
        }

        /// Check if key exists in any map
        pub fn contains(self: Self, key: K) bool {
            for (self.maps.items) |map| {
                if (map.contains(key)) return true;
            }
            return false;
        }

        /// Put key/value in the first (child) map
        pub fn put(self: *Self, key: K, value: V) !void {
            if (self.maps.items.len > 0) {
                try self.maps.items[0].put(key, value);
            }
        }

        /// Remove key from the first (child) map
        pub fn remove(self: *Self, key: K) bool {
            if (self.maps.items.len > 0) {
                return self.maps.items[0].remove(key);
            }
            return false;
        }

        /// Return a new ChainMap with a new map followed by all previous maps
        pub fn new_child(self: *Self, child: ?*std.AutoHashMap(K, V)) !Self {
            var new = Self.init(self.allocator);
            if (child) |c| {
                try new.maps.append(self.allocator, c);
            } else {
                const new_map = try self.allocator.create(std.AutoHashMap(K, V));
                new_map.* = std.AutoHashMap(K, V).init(self.allocator);
                try new.maps.append(self.allocator, new_map);
            }
            for (self.maps.items) |map| {
                try new.maps.append(self.allocator, map);
            }
            return new;
        }

        /// Return a new ChainMap containing all maps except the first
        pub fn parents(self: *Self) !Self {
            var new = Self.init(self.allocator);
            if (self.maps.items.len > 1) {
                for (self.maps.items[1..]) |map| {
                    try new.maps.append(self.allocator, map);
                }
            }
            return new;
        }

        /// Get count of unique keys across all maps
        pub fn count(self: Self) usize {
            var seen = std.AutoHashMap(K, void).init(self.allocator);
            defer seen.deinit();
            for (self.maps.items) |map| {
                var it = map.keyIterator();
                while (it.next()) |key| {
                    seen.put(key.*, {}) catch {};
                }
            }
            return seen.count();
        }
    };
}

//! ChainMap - Group of dicts treated as a single mapping
//!
//! Mirrors: CPython Lib/collections/__init__.py - ChainMap

const std = @import("std");

/// A group of dicts treated as a single mapping
pub fn ChainMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMap(K, V);

        allocator: std.mem.Allocator,
        maps: std.ArrayList(*Map),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .maps = std.ArrayList(*Map).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.maps.deinit();
        }

        /// Add a new map to the chain
        pub fn addMap(self: *Self, map: *Map) !void {
            try self.maps.append(map);
        }

        /// Get value, searching maps in order
        pub fn get(self: Self, key: K) ?V {
            for (self.maps.items) |map| {
                if (map.get(key)) |val| {
                    return val;
                }
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

        /// Get the first map (the one updates go to)
        pub fn first(self: Self) ?*Map {
            if (self.maps.items.len > 0) {
                return self.maps.items[0];
            }
            return null;
        }

        /// Create new ChainMap with additional map in front
        pub fn newChild(self: Self, map: ?*Map, allocator: std.mem.Allocator) !Self {
            var result = Self.init(allocator);
            if (map) |m| {
                try result.maps.append(m);
            }
            for (self.maps.items) |m| {
                try result.maps.append(m);
            }
            return result;
        }

        /// Return parents (all maps except first)
        pub fn parents(self: Self, allocator: std.mem.Allocator) !Self {
            var result = Self.init(allocator);
            if (self.maps.items.len > 1) {
                for (self.maps.items[1..]) |m| {
                    try result.maps.append(m);
                }
            }
            return result;
        }
    };
}

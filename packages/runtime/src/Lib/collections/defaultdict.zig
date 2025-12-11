//! defaultdict - Dict with default value factory
//!
//! Mirrors: CPython Lib/collections/__init__.py - defaultdict

const std = @import("std");

/// Dict with default value factory
pub fn DefaultDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        map: std.AutoHashMap(K, V),
        default_value: V,

        pub fn init(allocator: std.mem.Allocator, default_value: V) Self {
            return .{
                .allocator = allocator,
                .map = std.AutoHashMap(K, V).init(allocator),
                .default_value = default_value,
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn get(self: *Self, key: K) !V {
            const entry = try self.map.getOrPut(key);
            if (!entry.found_existing) {
                entry.value_ptr.* = self.default_value;
            }
            return entry.value_ptr.*;
        }

        pub fn getExisting(self: Self, key: K) ?V {
            return self.map.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            try self.map.put(key, value);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.map.contains(key);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.map.remove(key);
        }

        pub fn len(self: Self) usize {
            return self.map.count();
        }

        pub fn clear(self: *Self) void {
            self.map.clearRetainingCapacity();
        }
    };
}

test "DefaultDict" {
    const allocator = std.testing.allocator;

    var dd = DefaultDict([]const u8, i32).init(allocator, 0);
    defer dd.deinit();

    try dd.put("a", 10);
    try std.testing.expectEqual(@as(i32, 10), try dd.get("a"));
    try std.testing.expectEqual(@as(i32, 0), try dd.get("missing"));
}

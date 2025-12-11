/// Hash set implementation (table with no values)
/// Mirrors cpython/Python/hashtable.c set functionality

const std = @import("std");
const Allocator = std.mem.Allocator;
const hash_table = @import("hash_table.zig");

/// Hash set (table with no values)
pub fn HashSet(comptime K: type) type {
    return struct {
        table: hash_table.HashTable(K, void),

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{ .table = try hash_table.HashTable(K, void).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.table.deinit();
        }

        pub fn add(self: *Self, key: K) !void {
            try self.table.put(key, {});
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.table.remove(key);
        }

        pub fn contains(self: *Self, key: K) bool {
            return self.table.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.table.size;
        }

        pub fn clear(self: *Self) void {
            self.table.clear();
        }
    };
}

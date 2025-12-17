//! Counter - Count hashable elements
//!
//! Mirrors: CPython Lib/collections/__init__.py - Counter

const std = @import("std");

/// Dict subclass for counting hashable objects
pub fn Counter(comptime T: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMap(T, i64);

        allocator: std.mem.Allocator,
        counts: Map,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .counts = Map.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.counts.deinit();
        }

        /// Update counts from iterable
        pub fn update(self: *Self, items: []const T) !void {
            for (items) |item| {
                const entry = try self.counts.getOrPut(item);
                if (entry.found_existing) {
                    entry.value_ptr.* += 1;
                } else {
                    entry.value_ptr.* = 1;
                }
            }
        }

        /// Get count for element
        pub fn get(self: Self, key: T) i64 {
            return self.counts.get(key) orelse 0;
        }

        /// Set count for element
        pub fn set(self: *Self, key: T, count_val: i64) !void {
            try self.counts.put(key, count_val);
        }

        /// Remove all zero and negative counts
        pub fn keepPositive(self: *Self) void {
            var iter = self.counts.iterator();
            var to_remove: std.ArrayList(T) = .{};
            defer to_remove.deinit(self.allocator);

            while (iter.next()) |entry| {
                if (entry.value_ptr.* <= 0) {
                    to_remove.append(self.allocator, entry.key_ptr.*) catch unreachable;
                }
            }

            for (to_remove.items) |key| {
                _ = self.counts.remove(key);
            }
        }

        /// Return list of (element, count) pairs
        pub fn elements(self: Self, allocator: std.mem.Allocator) ![]T {
            var result: std.ArrayList(T) = .{};
            errdefer result.deinit(allocator);

            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                var i: i64 = 0;
                while (i < entry.value_ptr.*) : (i += 1) {
                    try result.append(allocator, entry.key_ptr.*);
                }
            }

            return result.toOwnedSlice(allocator);
        }

        /// Return n most common elements
        pub fn mostCommon(self: Self, allocator: std.mem.Allocator, n: ?usize) ![]struct { key: T, count: i64 } {
            const Entry = struct { key: T, count: i64 };

            var list: std.ArrayList(Entry) = .{};
            errdefer list.deinit(allocator);

            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                try list.append(allocator, .{ .key = entry.key_ptr.*, .count = entry.value_ptr.* });
            }

            // Sort by count descending
            std.mem.sort(Entry, list.items, {}, struct {
                fn lessThan(_: void, a: Entry, b: Entry) bool {
                    return a.count > b.count;
                }
            }.lessThan);

            const limit = n orelse list.items.len;
            const result_len = @min(limit, list.items.len);
            return try allocator.dupe(Entry, list.items[0..result_len]);
        }

        /// Add two counters
        pub fn add(self: Self, other: Self, allocator: std.mem.Allocator) !Self {
            var result = Self.init(allocator);

            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                try result.set(entry.key_ptr.*, entry.value_ptr.*);
            }

            var other_iter = other.counts.iterator();
            while (other_iter.next()) |entry| {
                const current = result.get(entry.key_ptr.*);
                try result.set(entry.key_ptr.*, current + entry.value_ptr.*);
            }

            return result;
        }

        /// Subtract another counter
        pub fn subtract(self: *Self, other: Self) void {
            var iter = other.counts.iterator();
            while (iter.next()) |entry| {
                const current = self.get(entry.key_ptr.*);
                self.set(entry.key_ptr.*, current - entry.value_ptr.*) catch {};
            }
        }

        /// Total of all counts
        pub fn total(self: Self) i64 {
            var sum: i64 = 0;
            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                sum += entry.value_ptr.*;
            }
            return sum;
        }

        /// Number of unique elements
        pub fn len(self: Self) usize {
            return self.counts.count();
        }

        /// Clear all counts
        pub fn clear(self: *Self) void {
            self.counts.clearRetainingCapacity();
        }
    };
}

test "Counter" {
    const allocator = std.testing.allocator;

    var c = Counter(u8).init(allocator);
    defer c.deinit();

    try c.update("abracadabra");

    try std.testing.expectEqual(@as(i64, 5), c.get('a'));
    try std.testing.expectEqual(@as(i64, 2), c.get('b'));
    try std.testing.expectEqual(@as(i64, 2), c.get('r'));
}

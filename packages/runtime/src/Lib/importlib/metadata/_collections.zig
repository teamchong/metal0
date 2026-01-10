//! importlib.metadata._collections - Collection utilities
//! Reference: cpython/Lib/importlib/metadata/_collections.py
//!
//! CPython exports: FreezableDefaultDict, Pair

const std = @import("std");

/// Pair - Simple key-value pair
/// CPython: class Pair
pub const Pair = struct {
    name: ?[]const u8,
    value: []const u8,

    pub fn init(name: ?[]const u8, value: []const u8) Pair {
        return .{ .name = name, .value = value };
    }

    /// Parse a "key = value" string into a Pair
    pub fn parse(text: []const u8) Pair {
        const eq_pos = std.mem.indexOf(u8, text, "=") orelse return Pair.init(null, text);
        const name = std.mem.trim(u8, text[0..eq_pos], " \t");
        const value = std.mem.trim(u8, text[eq_pos + 1 ..], " \t");
        return Pair.init(name, value);
    }
};

/// FreezableDefaultDict - Dict that can be frozen
/// CPython: class FreezableDefaultDict(defaultdict)
pub fn FreezableDefaultDict(comptime V: type) type {
    return struct {
        const Self = @This();

        data: std.StringHashMap(std.ArrayList(V)),
        allocator: std.mem.Allocator,
        frozen: bool = false,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .data = std.StringHashMap(std.ArrayList(V)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.data.valueIterator();
            while (iter.next()) |list| {
                list.deinit(self.allocator);
            }
            self.data.deinit();
        }

        pub fn get(self: *const Self, key: []const u8) ?std.ArrayList(V) {
            return self.data.get(key);
        }

        pub fn put(self: *Self, key: []const u8, value: V) !void {
            if (self.frozen) return error.Frozen;
            var list = self.data.get(key) orelse std.ArrayList(V){};
            try list.append(self.allocator, value);
            try self.data.put(key, list);
        }

        pub fn freeze(self: *Self) void {
            self.frozen = true;
        }
    };
}

test "Pair parse" {
    const pair = Pair.parse("key = value");
    try std.testing.expectEqualStrings("key", pair.name.?);
    try std.testing.expectEqualStrings("value", pair.value);
}

test "FreezableDefaultDict" {
    const allocator = std.testing.allocator;
    var dict = FreezableDefaultDict([]const u8).init(allocator);
    defer dict.deinit();

    try dict.put("key", "value1");
    try dict.put("key", "value2");
    try std.testing.expectEqual(@as(usize, 2), dict.get("key").?.items.len);

    dict.freeze();
    try std.testing.expectError(error.Frozen, dict.put("key", "value3"));
}

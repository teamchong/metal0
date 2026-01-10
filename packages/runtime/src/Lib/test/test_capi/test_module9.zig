//! test.test_capi.test_module9 - C API Module Tests Part 9 - Mapping Protocol
const std = @import("std");

/// Mapping protocol implementation
pub fn Mapping(comptime K: type, comptime V: type) type {
    return struct {
        items: std.AutoHashMap(K, V),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .items = std.AutoHashMap(K, V).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn len(self: *const Self) usize {
            return self.items.count();
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.items.get(key);
        }

        pub fn set(self: *Self, key: K, value: V) !void {
            try self.items.put(key, value);
        }

        pub fn delete(self: *Self, key: K) bool {
            return self.items.remove(key);
        }

        pub fn contains(self: *const Self, key: K) bool {
            return self.items.contains(key);
        }

        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        pub fn keys(self: *const Self) KeyIterator {
            return .{ .iter = self.items.keyIterator() };
        }

        pub fn values(self: *const Self) ValueIterator {
            return .{ .iter = self.items.valueIterator() };
        }

        pub const KeyIterator = struct {
            iter: std.AutoHashMap(K, V).KeyIterator,

            pub fn next(self: *KeyIterator) ?K {
                return self.iter.next();
            }
        };

        pub const ValueIterator = struct {
            iter: std.AutoHashMap(K, V).ValueIterator,

            pub fn next(self: *ValueIterator) ?V {
                return self.iter.next().*;
            }
        };
    };
}

/// String-keyed dictionary
pub const StringDict = struct {
    items: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub const Value = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        none: void,
    };

    pub fn init(allocator: std.mem.Allocator) StringDict {
        return .{
            .items = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StringDict) void {
        self.items.deinit();
    }

    pub fn len(self: *const StringDict) usize {
        return self.items.count();
    }

    pub fn get(self: *const StringDict, key: []const u8) ?Value {
        return self.items.get(key);
    }

    pub fn set(self: *StringDict, key: []const u8, value: Value) !void {
        try self.items.put(key, value);
    }

    pub fn setDefault(self: *StringDict, key: []const u8, default: Value) !Value {
        if (self.items.get(key)) |v| return v;
        try self.items.put(key, default);
        return default;
    }

    pub fn pop(self: *StringDict, key: []const u8) ?Value {
        if (self.items.fetchRemove(key)) |kv| {
            return kv.value;
        }
        return null;
    }

    pub fn update(self: *StringDict, other: *const StringDict) !void {
        var it = other.items.iterator();
        while (it.next()) |entry| {
            try self.items.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
};

/// Counter for counting occurrences
pub fn Counter(comptime T: type) type {
    return struct {
        counts: std.AutoHashMap(T, usize),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .counts = std.AutoHashMap(T, usize).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.counts.deinit();
        }

        pub fn add(self: *Self, item: T) !void {
            const entry = try self.counts.getOrPut(item);
            if (entry.found_existing) {
                entry.value_ptr.* += 1;
            } else {
                entry.value_ptr.* = 1;
            }
        }

        pub fn get(self: *const Self, item: T) usize {
            return self.counts.get(item) orelse 0;
        }

        pub fn total(self: *const Self) usize {
            var sum: usize = 0;
            var it = self.counts.valueIterator();
            while (it.next()) |count| {
                sum += count.*;
            }
            return sum;
        }
    };
}

test "Mapping basic" {
    const allocator = std.testing.allocator;
    var map = Mapping(i32, []const u8).init(allocator);
    defer map.deinit();

    try map.set(1, "one");
    try map.set(2, "two");

    try std.testing.expectEqual(@as(usize, 2), map.len());
    try std.testing.expectEqualStrings("one", map.get(1).?);
    try std.testing.expect(map.contains(2));
}

test "Mapping delete" {
    const allocator = std.testing.allocator;
    var map = Mapping(i32, i32).init(allocator);
    defer map.deinit();

    try map.set(1, 100);
    try std.testing.expect(map.contains(1));

    try std.testing.expect(map.delete(1));
    try std.testing.expect(!map.contains(1));
}

test "StringDict" {
    const allocator = std.testing.allocator;
    var dict = StringDict.init(allocator);
    defer dict.deinit();

    try dict.set("name", .{ .string = "Alice" });
    try dict.set("age", .{ .int = 30 });

    try std.testing.expectEqual(@as(usize, 2), dict.len());
    try std.testing.expectEqualStrings("Alice", dict.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 30), dict.get("age").?.int);
}

test "StringDict setDefault" {
    const allocator = std.testing.allocator;
    var dict = StringDict.init(allocator);
    defer dict.deinit();

    const v1 = try dict.setDefault("key", .{ .int = 42 });
    try std.testing.expectEqual(@as(i64, 42), v1.int);

    try dict.set("key", .{ .int = 100 });
    const v2 = try dict.setDefault("key", .{ .int = 0 });
    try std.testing.expectEqual(@as(i64, 100), v2.int);
}

test "Counter" {
    const allocator = std.testing.allocator;
    var counter = Counter(u8).init(allocator);
    defer counter.deinit();

    try counter.add('a');
    try counter.add('b');
    try counter.add('a');
    try counter.add('a');

    try std.testing.expectEqual(@as(usize, 3), counter.get('a'));
    try std.testing.expectEqual(@as(usize, 1), counter.get('b'));
    try std.testing.expectEqual(@as(usize, 0), counter.get('c'));
    try std.testing.expectEqual(@as(usize, 4), counter.total());
}

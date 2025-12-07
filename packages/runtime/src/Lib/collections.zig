//! Python 'collections' module - Container datatypes
//!
//! This module implements specialized container datatypes providing
//! alternatives to Python's general purpose built-in containers.
//!
//! Mirrors: CPython Lib/collections/__init__.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// namedtuple
// ============================================================================

/// Create a namedtuple type with given field names
pub fn namedtuple(comptime name: []const u8, comptime fields: []const []const u8) type {
    return struct {
        const Self = @This();
        pub const _name = name;
        pub const _fields = fields;

        values: [fields.len][]const u8,

        /// Create a new named tuple
        pub fn init(values: [fields.len][]const u8) Self {
            return .{ .values = values };
        }

        /// Get value by field name
        pub fn get(self: Self, comptime field_name: []const u8) []const u8 {
            inline for (fields, 0..) |f, i| {
                if (comptime std.mem.eql(u8, f, field_name)) {
                    return self.values[i];
                }
            }
            @compileError("Unknown field: " ++ field_name);
        }

        /// Get value by index
        pub fn getIndex(self: Self, index: usize) ?[]const u8 {
            if (index < fields.len) {
                return self.values[index];
            }
            return null;
        }

        /// Convert to slice
        pub fn toSlice(self: Self) []const []const u8 {
            return &self.values;
        }

        /// Get the number of fields
        pub fn len() usize {
            return fields.len;
        }

        /// Replace values
        pub fn replace(self: Self, comptime field_name: []const u8, new_value: []const u8) Self {
            var result = self;
            inline for (fields, 0..) |f, i| {
                if (comptime std.mem.eql(u8, f, field_name)) {
                    result.values[i] = new_value;
                    return result;
                }
            }
            @compileError("Unknown field: " ++ field_name);
        }

        /// Convert to dict-like representation
        pub fn asDict(self: Self, allocator: std.mem.Allocator) !hashmap_helper.StringHashMap([]const u8) {
            var dict = hashmap_helper.StringHashMap([]const u8).init(allocator);
            errdefer dict.deinit();
            inline for (fields, 0..) |f, i| {
                try dict.put(f, self.values[i]);
            }
            return dict;
        }
    };
}

// ============================================================================
// deque - Double-ended queue
// ============================================================================

/// Double-ended queue with O(1) append/pop on both ends
pub fn Deque(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            value: T,
            prev: ?*Node = null,
            next: ?*Node = null,
        };

        allocator: std.mem.Allocator,
        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,
        maxlen: ?usize = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn initMaxlen(allocator: std.mem.Allocator, maxlen: usize) Self {
            return .{ .allocator = allocator, .maxlen = maxlen };
        }

        pub fn deinit(self: *Self) void {
            self.clear();
        }

        /// Add to right end
        pub fn append(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .value = value, .prev = self.tail, .next = null };

            if (self.tail) |tail| {
                tail.next = node;
            } else {
                self.head = node;
            }
            self.tail = node;
            self.len += 1;

            // Enforce maxlen
            if (self.maxlen) |ml| {
                while (self.len > ml) {
                    _ = self.popleft() catch break;
                }
            }
        }

        /// Add to left end
        pub fn appendleft(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .value = value, .prev = null, .next = self.head };

            if (self.head) |head| {
                head.prev = node;
            } else {
                self.tail = node;
            }
            self.head = node;
            self.len += 1;

            // Enforce maxlen
            if (self.maxlen) |ml| {
                while (self.len > ml) {
                    _ = self.pop() catch break;
                }
            }
        }

        /// Remove and return from right end
        pub fn pop(self: *Self) !T {
            const node = self.tail orelse return error.Empty;
            const value = node.value;

            if (node.prev) |prev| {
                prev.next = null;
                self.tail = prev;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.allocator.destroy(node);
            self.len -= 1;
            return value;
        }

        /// Remove and return from left end
        pub fn popleft(self: *Self) !T {
            const node = self.head orelse return error.Empty;
            const value = node.value;

            if (node.next) |next| {
                next.prev = null;
                self.head = next;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.allocator.destroy(node);
            self.len -= 1;
            return value;
        }

        /// Extend right with iterable
        pub fn extend(self: *Self, items: []const T) !void {
            for (items) |item| {
                try self.append(item);
            }
        }

        /// Extend left with iterable
        pub fn extendleft(self: *Self, items: []const T) !void {
            for (items) |item| {
                try self.appendleft(item);
            }
        }

        /// Rotate n steps to the right
        pub fn rotate(self: *Self, n: i32) !void {
            if (self.len <= 1 or n == 0) return;

            const steps = @mod(n, @as(i32, @intCast(self.len)));
            if (steps == 0) return;

            if (steps > 0) {
                var i: i32 = 0;
                while (i < steps) : (i += 1) {
                    const val = try self.pop();
                    try self.appendleft(val);
                }
            } else {
                var i: i32 = 0;
                while (i < -steps) : (i += 1) {
                    const val = try self.popleft();
                    try self.append(val);
                }
            }
        }

        /// Remove all elements
        pub fn clear(self: *Self) void {
            while (self.head) |node| {
                self.head = node.next;
                self.allocator.destroy(node);
            }
            self.tail = null;
            self.len = 0;
        }

        /// Count occurrences of value
        pub fn count(self: Self, value: T) usize {
            var c: usize = 0;
            var node = self.head;
            while (node) |n| {
                if (n.value == value) c += 1;
                node = n.next;
            }
            return c;
        }

        /// Reverse in place
        pub fn reverse(self: *Self) void {
            var node = self.head;
            while (node) |n| {
                const tmp = n.prev;
                n.prev = n.next;
                n.next = tmp;
                node = n.prev; // Was next, now prev
            }
            const tmp = self.head;
            self.head = self.tail;
            self.tail = tmp;
        }

        /// Copy to new deque
        pub fn copy(self: Self, allocator: std.mem.Allocator) !Self {
            var result = Self.init(allocator);
            result.maxlen = self.maxlen;

            var node = self.head;
            while (node) |n| {
                try result.append(n.value);
                node = n.next;
            }
            return result;
        }

        /// Get item at index (negative indices supported)
        pub fn getItem(self: Self, index: i32) ?T {
            const actual_idx = if (index < 0)
                @as(usize, @intCast(@as(i32, @intCast(self.len)) + index))
            else
                @as(usize, @intCast(index));

            if (actual_idx >= self.len) return null;

            var node = self.head;
            var i: usize = 0;
            while (node) |n| {
                if (i == actual_idx) return n.value;
                node = n.next;
                i += 1;
            }
            return null;
        }
    };
}

// ============================================================================
// Counter - Count hashable elements
// ============================================================================

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
            var to_remove = std.ArrayList(T).init(self.allocator);
            defer to_remove.deinit();

            while (iter.next()) |entry| {
                if (entry.value_ptr.* <= 0) {
                    to_remove.append(entry.key_ptr.*) catch {};
                }
            }

            for (to_remove.items) |key| {
                _ = self.counts.remove(key);
            }
        }

        /// Return list of (element, count) pairs
        pub fn elements(self: Self, allocator: std.mem.Allocator) ![]T {
            var result = std.ArrayList(T).init(allocator);
            errdefer result.deinit();

            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                var i: i64 = 0;
                while (i < entry.value_ptr.*) : (i += 1) {
                    try result.append(entry.key_ptr.*);
                }
            }

            return result.toOwnedSlice();
        }

        /// Return n most common elements
        pub fn mostCommon(self: Self, allocator: std.mem.Allocator, n: ?usize) ![]struct { key: T, count: i64 } {
            const Entry = struct { key: T, count: i64 };

            var list = std.ArrayList(Entry).init(allocator);
            errdefer list.deinit();

            var iter = self.counts.iterator();
            while (iter.next()) |entry| {
                try list.append(.{ .key = entry.key_ptr.*, .count = entry.value_ptr.* });
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

// ============================================================================
// OrderedDict
// ============================================================================

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
            if (self.map.fetchRemove(key)) |kv| {
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

// ============================================================================
// defaultdict
// ============================================================================

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

// ============================================================================
// ChainMap
// ============================================================================

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

// ============================================================================
// UserDict, UserList, UserString wrappers
// ============================================================================

/// Wrapper around dict for easier subclassing
pub fn UserDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        data: std.AutoHashMap(K, V),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .data = std.AutoHashMap(K, V).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: Self, key: K) ?V {
            return self.data.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            try self.data.put(key, value);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.data.contains(key);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.data.remove(key);
        }

        pub fn len(self: Self) usize {
            return self.data.count();
        }
    };
}

/// Wrapper around list for easier subclassing
pub fn UserList(comptime T: type) type {
    return struct {
        const Self = @This();
        data: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .data = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn append(self: *Self, item: T) !void {
            try self.data.append(item);
        }

        pub fn get(self: Self, index: usize) ?T {
            if (index < self.data.items.len) {
                return self.data.items[index];
            }
            return null;
        }

        pub fn len(self: Self) usize {
            return self.data.items.len;
        }

        pub fn pop(self: *Self) ?T {
            return self.data.popOrNull();
        }
    };
}

/// Wrapper around string for easier subclassing
pub const UserString = struct {
    data: []const u8,

    pub fn init(s: []const u8) UserString {
        return .{ .data = s };
    }

    pub fn len(self: UserString) usize {
        return self.data.len;
    }

    pub fn str(self: UserString) []const u8 {
        return self.data;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "namedtuple" {
    const Point = namedtuple("Point", &.{ "x", "y" });
    const p = Point.init(.{ "10", "20" });

    try std.testing.expectEqualStrings("10", p.get("x"));
    try std.testing.expectEqualStrings("20", p.get("y"));
    try std.testing.expectEqual(@as(usize, 2), Point.len());
}

test "Deque" {
    const allocator = std.testing.allocator;

    var dq = Deque(i32).init(allocator);
    defer dq.deinit();

    try dq.append(1);
    try dq.append(2);
    try dq.appendleft(0);

    try std.testing.expectEqual(@as(usize, 3), dq.len);
    try std.testing.expectEqual(@as(i32, 0), try dq.popleft());
    try std.testing.expectEqual(@as(i32, 2), try dq.pop());
}

test "Deque maxlen" {
    const allocator = std.testing.allocator;

    var dq = Deque(i32).initMaxlen(allocator, 3);
    defer dq.deinit();

    try dq.append(1);
    try dq.append(2);
    try dq.append(3);
    try dq.append(4); // Should remove 1

    try std.testing.expectEqual(@as(usize, 3), dq.len);
    try std.testing.expectEqual(@as(i32, 2), dq.getItem(0).?);
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

test "DefaultDict" {
    const allocator = std.testing.allocator;

    var dd = DefaultDict([]const u8, i32).init(allocator, 0);
    defer dd.deinit();

    try dd.put("a", 10);
    try std.testing.expectEqual(@as(i32, 10), try dd.get("a"));
    try std.testing.expectEqual(@as(i32, 0), try dd.get("missing"));
}

test "UserList" {
    const allocator = std.testing.allocator;

    var ul = UserList(i32).init(allocator);
    defer ul.deinit();

    try ul.append(1);
    try ul.append(2);

    try std.testing.expectEqual(@as(usize, 2), ul.len());
    try std.testing.expectEqual(@as(i32, 1), ul.get(0).?);
}

test "UserString" {
    const us = UserString.init("hello");
    try std.testing.expectEqual(@as(usize, 5), us.len());
    try std.testing.expectEqualStrings("hello", us.str());
}

/// _collections - C accelerator module for collections
/// Provides: deque, defaultdict, OrderedDict, Counter
const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// deque - Double-ended queue
// ============================================================================

/// deque([iterable[, maxlen]]) -> deque object
/// A list-like sequence optimized for data accesses near its endpoints.
pub fn Deque(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        maxlen: ?usize,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .maxlen = null,
                .allocator = allocator,
            };
        }

        pub fn initWithMaxlen(allocator: Allocator, maxlen: usize) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
                .maxlen = maxlen,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        /// Add an element to the right side of the deque
        pub fn append(self: *Self, value: T) !void {
            if (self.maxlen) |max| {
                if (self.items.items.len >= max) {
                    _ = self.items.orderedRemove(0);
                }
            }
            try self.items.append(self.allocator, value);
        }

        /// Add an element to the left side of the deque
        pub fn appendleft(self: *Self, value: T) !void {
            if (self.maxlen) |max| {
                if (self.items.items.len >= max) {
                    _ = self.items.pop();
                }
            }
            try self.items.insert(self.allocator, 0, value);
        }

        /// Remove and return an element from the right side
        pub fn pop(self: *Self) ?T {
            return self.items.popOrNull();
        }

        /// Remove and return an element from the left side
        pub fn popleft(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.orderedRemove(0);
        }

        /// Extend the right side with elements from iterable
        pub fn extend(self: *Self, values: []const T) !void {
            for (values) |v| {
                try self.append(v);
            }
        }

        /// Extend the left side with elements from iterable
        pub fn extendleft(self: *Self, values: []const T) !void {
            // Note: extendleft reverses the order
            var i: usize = values.len;
            while (i > 0) {
                i -= 1;
                try self.appendleft(values[i]);
            }
        }

        /// Rotate the deque n steps to the right (negative for left)
        pub fn rotate(self: *Self, n: i32) void {
            if (self.items.items.len <= 1) return;

            const item_len = self.items.items.len;
            const steps: usize = @intCast(@mod(n, @as(i32, @intCast(item_len))));

            if (steps == 0) return;

            // Rotate right by moving last `steps` elements to front
            var temp = std.ArrayList(T).init(self.allocator);
            defer temp.deinit(self.allocator);

            // This is a simplified rotation - could be optimized
            for (0..steps) |_| {
                if (self.pop()) |v| {
                    temp.insert(self.allocator, 0, v) catch {};
                }
            }
            for (temp.items) |v| {
                self.items.insert(self.allocator, 0, v) catch {};
            }
        }

        /// Remove all elements from the deque
        pub fn clear(self: *Self) void {
            self.items.clearRetainingCapacity();
        }

        /// Count the number of deque elements equal to x
        pub fn count(self: Self, value: T) usize {
            var c: usize = 0;
            for (self.items.items) |item| {
                if (item == value) c += 1;
            }
            return c;
        }

        /// Return the index of the first occurrence of value
        pub fn index(self: Self, value: T) ?usize {
            for (self.items.items, 0..) |item, i| {
                if (item == value) return i;
            }
            return null;
        }

        /// Insert value at position i
        pub fn insert(self: *Self, i: usize, value: T) !void {
            const pos = @min(i, self.items.items.len);
            try self.items.insert(self.allocator, pos, value);
            if (self.maxlen) |max| {
                while (self.items.items.len > max) {
                    _ = self.items.pop();
                }
            }
        }

        /// Remove first occurrence of value
        pub fn remove(self: *Self, value: T) !void {
            for (self.items.items, 0..) |item, i| {
                if (item == value) {
                    _ = self.items.orderedRemove(i);
                    return;
                }
            }
            return error.ValueError;
        }

        /// Reverse the elements of the deque in-place
        pub fn reverse(self: *Self) void {
            std.mem.reverse(T, self.items.items);
        }

        /// Return the number of elements
        pub fn len(self: Self) usize {
            return self.items.items.len;
        }

        /// Get element at index
        pub fn get(self: Self, i: usize) ?T {
            if (i >= self.items.items.len) return null;
            return self.items.items[i];
        }

        /// Set element at index
        pub fn set(self: *Self, i: usize, value: T) !void {
            if (i >= self.items.items.len) return error.IndexError;
            self.items.items[i] = value;
        }

        /// Copy deque to slice
        pub fn copy(self: Self) []const T {
            return self.items.items;
        }
    };
}

// ============================================================================
// defaultdict - Dictionary with default factory
// ============================================================================

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
    };
}

// ============================================================================
// OrderedDict - Dictionary that remembers insertion order
// Note: In Python 3.7+, regular dict maintains order, but OrderedDict has
// additional methods like move_to_end
// ============================================================================

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
                .order = std.ArrayList(K).init(allocator),
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
                self.order.pop()
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
    };
}

// ============================================================================
// Counter - Dict subclass for counting hashable objects
// ============================================================================

/// Counter([iterable-or-mapping]) -> Counter object for counting
pub fn Counter(comptime T: type) type {
    return struct {
        counts: std.AutoHashMap(T, i64),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .counts = std.AutoHashMap(T, i64).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.counts.deinit();
        }

        /// Initialize from iterable
        pub fn fromIterable(allocator: Allocator, items: []const T) !Self {
            var self = Self.init(allocator);
            for (items) |item| {
                try self.increment(item);
            }
            return self;
        }

        /// Increment count for element
        pub fn increment(self: *Self, elem: T) !void {
            const entry = try self.counts.getOrPut(elem);
            if (!entry.found_existing) {
                entry.value_ptr.* = 0;
            }
            entry.value_ptr.* += 1;
        }

        /// Get count for element (0 if not present)
        pub fn get(self: Self, elem: T) i64 {
            return self.counts.get(elem) orelse 0;
        }

        /// Set count for element
        pub fn set(self: *Self, elem: T, count: i64) !void {
            if (count <= 0) {
                _ = self.counts.remove(elem);
            } else {
                try self.counts.put(elem, count);
            }
        }

        /// Return list of (elem, count) pairs, most common first
        pub fn most_common(self: Self, n: ?usize) ![]const struct { T, i64 } {
            var pairs = std.ArrayList(struct { T, i64 }).init(self.allocator);
            defer pairs.deinit(self.allocator);

            var it = self.counts.iterator();
            while (it.next()) |entry| {
                try pairs.append(self.allocator, .{ entry.key_ptr.*, entry.value_ptr.* });
            }

            // Sort by count descending
            std.mem.sort(struct { T, i64 }, pairs.items, {}, struct {
                fn cmp(_: void, a: struct { T, i64 }, b: struct { T, i64 }) bool {
                    return a[1] > b[1];
                }
            }.cmp);

            const limit = n orelse pairs.items.len;
            return pairs.items[0..@min(limit, pairs.items.len)];
        }

        /// Return iterator over elements repeating each as many times as its count
        pub fn elements(self: Self) ElementsIterator {
            return ElementsIterator.init(self);
        }

        const ElementsIterator = struct {
            counter: Self,
            key_iter: std.AutoHashMap(T, i64).Iterator,
            current_key: ?T,
            remaining: i64,

            fn init(counter: Self) ElementsIterator {
                var iter = ElementsIterator{
                    .counter = counter,
                    .key_iter = counter.counts.iterator(),
                    .current_key = null,
                    .remaining = 0,
                };
                iter.advanceKey();
                return iter;
            }

            fn advanceKey(self: *ElementsIterator) void {
                if (self.key_iter.next()) |entry| {
                    self.current_key = entry.key_ptr.*;
                    self.remaining = entry.value_ptr.*;
                } else {
                    self.current_key = null;
                    self.remaining = 0;
                }
            }

            pub fn next(self: *ElementsIterator) ?T {
                while (self.remaining <= 0) {
                    self.advanceKey();
                    if (self.current_key == null) return null;
                }
                self.remaining -= 1;
                return self.current_key;
            }
        };

        /// Add counts from another Counter
        pub fn update(self: *Self, other: Self) !void {
            var it = other.counts.iterator();
            while (it.next()) |entry| {
                const current = self.get(entry.key_ptr.*);
                try self.counts.put(entry.key_ptr.*, current + entry.value_ptr.*);
            }
        }

        /// Subtract counts from another Counter
        pub fn subtract(self: *Self, other: Self) !void {
            var it = other.counts.iterator();
            while (it.next()) |entry| {
                const current = self.get(entry.key_ptr.*);
                try self.counts.put(entry.key_ptr.*, current - entry.value_ptr.*);
            }
        }

        /// Return sum of all counts
        pub fn total(self: Self) i64 {
            var sum: i64 = 0;
            var it = self.counts.valueIterator();
            while (it.next()) |v| {
                sum += v.*;
            }
            return sum;
        }

        /// Clear all counts
        pub fn clear(self: *Self) void {
            self.counts.clearRetainingCapacity();
        }
    };
}

// ============================================================================
// _count_elements - Helper function used by Counter
// ============================================================================

/// Count elements from iterable into mapping
pub fn _count_elements(comptime T: type, counter: *Counter(T), iterable: []const T) !void {
    for (iterable) |elem| {
        try counter.increment(elem);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "deque basic operations" {
    const allocator = std.testing.allocator;
    var d = Deque(i32).init(allocator);
    defer d.deinit();

    try d.append(1);
    try d.append(2);
    try d.appendleft(0);

    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i32, 0), d.get(0));
    try std.testing.expectEqual(@as(?i32, 1), d.get(1));
    try std.testing.expectEqual(@as(?i32, 2), d.get(2));

    try std.testing.expectEqual(@as(?i32, 2), d.pop());
    try std.testing.expectEqual(@as(?i32, 0), d.popleft());
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "deque with maxlen" {
    const allocator = std.testing.allocator;
    var d = Deque(i32).initWithMaxlen(allocator, 3);
    defer d.deinit();

    try d.append(1);
    try d.append(2);
    try d.append(3);
    try d.append(4); // Should evict 1

    try std.testing.expectEqual(@as(usize, 3), d.len());
    try std.testing.expectEqual(@as(?i32, 2), d.get(0));
    try std.testing.expectEqual(@as(?i32, 4), d.get(2));
}

test "defaultdict" {
    const allocator = std.testing.allocator;

    const zero = struct {
        fn f() i32 {
            return 0;
        }
    }.f;

    var dd = DefaultDict(i32, i32).initWithFactory(allocator, zero);
    defer dd.deinit();

    // Missing key returns default
    const v1 = try dd.get(1);
    try std.testing.expectEqual(@as(i32, 0), v1);

    // Key now exists
    try std.testing.expect(dd.contains(1));

    // Set and get
    try dd.put(2, 42);
    try std.testing.expectEqual(@as(i32, 42), try dd.get(2));
}

test "counter" {
    const allocator = std.testing.allocator;

    const items = [_]u8{ 'a', 'b', 'a', 'c', 'a', 'b' };
    var counter = try Counter(u8).fromIterable(allocator, &items);
    defer counter.deinit();

    try std.testing.expectEqual(@as(i64, 3), counter.get('a'));
    try std.testing.expectEqual(@as(i64, 2), counter.get('b'));
    try std.testing.expectEqual(@as(i64, 1), counter.get('c'));
    try std.testing.expectEqual(@as(i64, 0), counter.get('d'));
    try std.testing.expectEqual(@as(i64, 6), counter.total());
}

test "ordered dict" {
    const allocator = std.testing.allocator;
    var od = OrderedDict(i32, i32).init(allocator);
    defer od.deinit();

    try od.put(1, 100);
    try od.put(2, 200);
    try od.put(3, 300);

    const keys = od.keys();
    try std.testing.expectEqual(@as(usize, 3), keys.len);
    try std.testing.expectEqual(@as(i32, 1), keys[0]);
    try std.testing.expectEqual(@as(i32, 2), keys[1]);
    try std.testing.expectEqual(@as(i32, 3), keys[2]);

    // Move 1 to end
    try od.move_to_end(1, true);
    const keys2 = od.keys();
    try std.testing.expectEqual(@as(i32, 2), keys2[0]);
    try std.testing.expectEqual(@as(i32, 3), keys2[1]);
    try std.testing.expectEqual(@as(i32, 1), keys2[2]);
}

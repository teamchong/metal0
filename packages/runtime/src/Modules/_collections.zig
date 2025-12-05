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
                .items = .empty,
                .maxlen = null,
                .allocator = allocator,
            };
        }

        pub fn initWithMaxlen(allocator: Allocator, maxlen: usize) Self {
            return .{
                .items = .empty,
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
            return self.items.pop();
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
                .order = .empty,
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
                self.order.pop() orelse return error.KeyError
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

        /// __reversed__ - Return reversed iterator over keys
        pub fn reversed(self: Self) ReversedIterator {
            return ReversedIterator.init(self);
        }

        const ReversedIterator = struct {
            order_items: []const K,
            index: usize,

            fn init(od: OrderedDict(K, V)) ReversedIterator {
                return .{
                    .order_items = od.order.items,
                    .index = od.order.items.len,
                };
            }

            pub fn next(self: *ReversedIterator) ?K {
                if (self.index == 0) return null;
                self.index -= 1;
                return self.order_items[self.index];
            }
        };

        /// __eq__ - Compare two OrderedDicts for equality
        /// Two OrderedDicts are equal if they have the same keys in the same order with same values
        pub fn eql(self: Self, other: Self) bool {
            // Check length first
            if (self.order.items.len != other.order.items.len) return false;

            // Check keys are in same order and values match
            for (self.order.items, 0..) |key, i| {
                // Keys must be in same order
                if (other.order.items[i] != key) return false;

                // Values must be equal
                const self_val = self.map.get(key);
                const other_val = other.map.get(key);
                if (self_val == null or other_val == null) return false;
                if (self_val.? != other_val.?) return false;
            }
            return true;
        }

        /// Copy the OrderedDict
        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            for (self.order.items) |key| {
                if (self.map.get(key)) |value| {
                    try new.put(key, value);
                }
            }
            return new;
        }

        /// setdefault - get or insert default
        pub fn setdefault(self: *Self, key: K, default: V) !V {
            if (self.map.get(key)) |v| {
                return v;
            }
            try self.put(key, default);
            return default;
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

        /// Counter addition: c1 + c2 (keeps only positive counts)
        pub fn add(self: Self, other: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            // Add all from self
            var it1 = self.counts.iterator();
            while (it1.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const new_count = entry.value_ptr.* + other_count;
                if (new_count > 0) {
                    try result.counts.put(entry.key_ptr.*, new_count);
                }
            }
            // Add items only in other
            var it2 = other.counts.iterator();
            while (it2.next()) |entry| {
                if (!self.counts.contains(entry.key_ptr.*)) {
                    if (entry.value_ptr.* > 0) {
                        try result.counts.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            }
            return result;
        }

        /// Counter subtraction: c1 - c2 (keeps only positive counts)
        pub fn sub(self: Self, other: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            var it = self.counts.iterator();
            while (it.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const new_count = entry.value_ptr.* - other_count;
                if (new_count > 0) {
                    try result.counts.put(entry.key_ptr.*, new_count);
                }
            }
            return result;
        }

        /// Counter intersection: c1 & c2 (min of counts)
        pub fn intersection(self: Self, other: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            var it = self.counts.iterator();
            while (it.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const min_count = @min(entry.value_ptr.*, other_count);
                if (min_count > 0) {
                    try result.counts.put(entry.key_ptr.*, min_count);
                }
            }
            return result;
        }

        /// Counter union: c1 | c2 (max of counts)
        pub fn @"union"(self: Self, other: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            // Add max from self vs other
            var it1 = self.counts.iterator();
            while (it1.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const max_count = @max(entry.value_ptr.*, other_count);
                if (max_count > 0) {
                    try result.counts.put(entry.key_ptr.*, max_count);
                }
            }
            // Add items only in other
            var it2 = other.counts.iterator();
            while (it2.next()) |entry| {
                if (!self.counts.contains(entry.key_ptr.*)) {
                    if (entry.value_ptr.* > 0) {
                        try result.counts.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }
            }
            return result;
        }

        /// Unary plus: +c (remove zero and negative counts)
        pub fn positive(self: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            var it = self.counts.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* > 0) {
                    try result.counts.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
            return result;
        }

        /// Unary minus: -c (negate counts, remove zeros and negatives)
        pub fn negative(self: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            var it = self.counts.iterator();
            while (it.next()) |entry| {
                const neg = -entry.value_ptr.*;
                if (neg > 0) {
                    try result.counts.put(entry.key_ptr.*, neg);
                }
            }
            return result;
        }

        /// fromkeys(iterable[, v]) - Create Counter from keys with specified count
        /// In Python: Counter.fromkeys(['a', 'b'], 0) creates Counter({'a': 0, 'b': 0})
        pub fn fromkeys(allocator: Allocator, keys_iter: []const T, value: i64) !Self {
            var result = Self.init(allocator);
            for (keys_iter) |key| {
                try result.counts.put(key, value);
            }
            return result;
        }

        /// copy - Return a shallow copy of the counter
        pub fn copyCounter(self: Self, allocator: Allocator) !Self {
            var result = Self.init(allocator);
            var it = self.counts.iterator();
            while (it.next()) |entry| {
                try result.counts.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return result;
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
// ChainMap - Dict-like class for creating a single view of multiple mappings
// ============================================================================

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
                try new.maps.append(c);
            } else {
                const new_map = try self.allocator.create(std.AutoHashMap(K, V));
                new_map.* = std.AutoHashMap(K, V).init(self.allocator);
                try new.maps.append(new_map);
            }
            for (self.maps.items) |map| {
                try new.maps.append(map);
            }
            return new;
        }

        /// Return a new ChainMap containing all maps except the first
        pub fn parents(self: *Self) !Self {
            var new = Self.init(self.allocator);
            if (self.maps.items.len > 1) {
                for (self.maps.items[1..]) |map| {
                    try new.maps.append(map);
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

// ============================================================================
// UserDict - Wrapper around dict for easier subclassing
// ============================================================================

/// UserDict - A wrapper around dictionary objects for easier subclassing
pub fn UserDict(comptime K: type, comptime V: type) type {
    return struct {
        data: std.AutoHashMap(K, V),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .data = std.AutoHashMap(K, V).init(allocator),
                .allocator = allocator,
            };
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

        pub fn remove(self: *Self, key: K) bool {
            return self.data.remove(key);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.data.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.data.count();
        }

        pub fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        pub fn keys(self: Self) std.AutoHashMap(K, V).KeyIterator {
            return self.data.keyIterator();
        }

        pub fn values(self: Self) std.AutoHashMap(K, V).ValueIterator {
            return self.data.valueIterator();
        }

        pub fn iterator(self: Self) std.AutoHashMap(K, V).Iterator {
            return self.data.iterator();
        }

        /// Copy the UserDict
        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            var it = self.data.iterator();
            while (it.next()) |entry| {
                try new.data.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return new;
        }

        /// Update with entries from another map
        pub fn update(self: *Self, other: anytype) !void {
            var it = other.iterator();
            while (it.next()) |entry| {
                try self.data.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        /// Get with default value
        pub fn getOrDefault(self: Self, key: K, default: V) V {
            return self.data.get(key) orelse default;
        }

        /// setdefault - get or insert default
        pub fn setdefault(self: *Self, key: K, default: V) !V {
            const entry = try self.data.getOrPut(key);
            if (!entry.found_existing) {
                entry.value_ptr.* = default;
            }
            return entry.value_ptr.*;
        }

        /// pop - remove and return value
        pub fn pop(self: *Self, key: K, default: ?V) ?V {
            if (self.data.fetchRemove(key)) |kv| {
                return kv.value;
            }
            return default;
        }

        /// popitem - remove and return arbitrary (key, value) pair
        pub fn popitem(self: *Self) ?struct { K, V } {
            var it = self.data.iterator();
            if (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                _ = self.data.remove(key);
                return .{ key, value };
            }
            return null;
        }
    };
}

// ============================================================================
// UserList - Wrapper around list for easier subclassing
// ============================================================================

/// UserList - A wrapper around list objects for easier subclassing
pub fn UserList(comptime T: type) type {
    return struct {
        data: std.ArrayList(T),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .data = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn append(self: *Self, value: T) !void {
            try self.data.append(value);
        }

        pub fn extend(self: *Self, values: []const T) !void {
            try self.data.appendSlice(values);
        }

        pub fn insert(self: *Self, idx: usize, value: T) !void {
            try self.data.insert(idx, value);
        }

        pub fn pop(self: *Self) ?T {
            return self.data.popOrNull();
        }

        pub fn remove(self: *Self, value: T) !void {
            for (self.data.items, 0..) |item, i| {
                if (item == value) {
                    _ = self.data.orderedRemove(i);
                    return;
                }
            }
            return error.ValueError;
        }

        pub fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        pub fn len(self: Self) usize {
            return self.data.items.len;
        }

        pub fn get(self: Self, idx: usize) ?T {
            if (idx >= self.data.items.len) return null;
            return self.data.items[idx];
        }

        pub fn set(self: *Self, idx: usize, value: T) !void {
            if (idx >= self.data.items.len) return error.IndexError;
            self.data.items[idx] = value;
        }

        pub fn index(self: Self, value: T) ?usize {
            for (self.data.items, 0..) |item, i| {
                if (item == value) return i;
            }
            return null;
        }

        pub fn count(self: Self, value: T) usize {
            var c: usize = 0;
            for (self.data.items) |item| {
                if (item == value) c += 1;
            }
            return c;
        }

        pub fn reverse(self: *Self) void {
            std.mem.reverse(T, self.data.items);
        }

        pub fn sort(self: *Self) void {
            std.mem.sort(T, self.data.items, {}, std.sort.asc(T));
        }

        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            try new.data.appendSlice(self.data.items);
            return new;
        }

        pub fn items(self: Self) []const T {
            return self.data.items;
        }
    };
}

// ============================================================================
// UserString - Wrapper around string for easier subclassing
// ============================================================================

/// UserString - A wrapper around string objects for easier subclassing
pub const UserString = struct {
    data: []const u8,
    allocator: Allocator,
    owned: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, str: []const u8) Self {
        return .{
            .data = str,
            .allocator = allocator,
            .owned = false,
        };
    }

    pub fn initOwned(allocator: Allocator, str: []const u8) !Self {
        const owned_str = try allocator.dupe(u8, str);
        return .{
            .data = owned_str,
            .allocator = allocator,
            .owned = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.owned) {
            self.allocator.free(@constCast(self.data));
        }
    }

    pub fn len(self: Self) usize {
        return self.data.len;
    }

    pub fn get(self: Self, index: usize) ?u8 {
        if (index >= self.data.len) return null;
        return self.data[index];
    }

    pub fn slice(self: Self, start: usize, end: usize) []const u8 {
        const s = @min(start, self.data.len);
        const e = @min(end, self.data.len);
        return self.data[s..e];
    }

    pub fn contains(self: Self, substr: []const u8) bool {
        return std.mem.indexOf(u8, self.data, substr) != null;
    }

    pub fn startswith(self: Self, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.data, prefix);
    }

    pub fn endswith(self: Self, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.data, suffix);
    }

    pub fn find(self: Self, substr: []const u8) ?usize {
        return std.mem.indexOf(u8, self.data, substr);
    }

    pub fn rfind(self: Self, substr: []const u8) ?usize {
        return std.mem.lastIndexOf(u8, self.data, substr);
    }

    pub fn count(self: Self, substr: []const u8) usize {
        var c: usize = 0;
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, self.data, i, substr)) |pos| {
            c += 1;
            i = pos + substr.len;
        }
        return c;
    }

    pub fn upper(self: *Self) !Self {
        var result = try self.allocator.alloc(u8, self.data.len);
        for (self.data, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }
        return .{
            .data = result,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn lower(self: *Self) !Self {
        var result = try self.allocator.alloc(u8, self.data.len);
        for (self.data, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return .{
            .data = result,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn strip(self: Self) []const u8 {
        return std.mem.trim(u8, self.data, " \t\n\r");
    }

    pub fn lstrip(self: Self) []const u8 {
        return std.mem.trimLeft(u8, self.data, " \t\n\r");
    }

    pub fn rstrip(self: Self) []const u8 {
        return std.mem.trimRight(u8, self.data, " \t\n\r");
    }

    pub fn isalpha(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isAlphabetic(c)) return false;
        }
        return true;
    }

    pub fn isdigit(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isDigit(c)) return false;
        }
        return true;
    }

    pub fn isalnum(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isAlphanumeric(c)) return false;
        }
        return true;
    }

    pub fn isspace(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isWhitespace(c)) return false;
        }
        return true;
    }

    pub fn replace(self: *Self, old: []const u8, new: []const u8) !Self {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < self.data.len) {
            if (i + old.len <= self.data.len and std.mem.eql(u8, self.data[i .. i + old.len], old)) {
                try result.appendSlice(new);
                i += old.len;
            } else {
                try result.append(self.data[i]);
                i += 1;
            }
        }

        const owned = try self.allocator.dupe(u8, result.items);
        return .{
            .data = owned,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn toString(self: Self) []const u8 {
        return self.data;
    }
};

// ============================================================================
// namedtuple - Factory function for creating tuple subclasses with named fields
// ============================================================================

/// NamedTuple - Runtime representation of a namedtuple
/// This provides the base functionality for namedtuple instances at runtime.
/// The actual namedtuple factory is handled by codegen which creates specialized types.
pub fn NamedTuple(comptime field_count: usize) type {
    return struct {
        _fields: [field_count][]const u8,
        _values: [field_count]i64, // Using i64 for generic value storage
        _typename: []const u8,

        const Self = @This();

        pub fn init(typename: []const u8, field_names: [field_count][]const u8, values: [field_count]i64) Self {
            return .{
                ._fields = field_names,
                ._values = values,
                ._typename = typename,
            };
        }

        /// Get field value by index
        pub fn get(self: Self, index: usize) ?i64 {
            if (index >= field_count) return null;
            return self._values[index];
        }

        /// Get field value by name
        pub fn getByName(self: Self, name: []const u8) ?i64 {
            for (self._fields, 0..) |field, i| {
                if (std.mem.eql(u8, field, name)) {
                    return self._values[i];
                }
            }
            return null;
        }

        /// Get field index by name
        pub fn fieldIndex(self: Self, name: []const u8) ?usize {
            for (self._fields, 0..) |field, i| {
                if (std.mem.eql(u8, field, name)) {
                    return i;
                }
            }
            return null;
        }

        /// _asdict() - Return a new dict mapping field names to values
        pub fn _asdict(self: Self, allocator: Allocator) !std.StringHashMap(i64) {
            var dict = std.StringHashMap(i64).init(allocator);
            for (self._fields, 0..) |field, i| {
                try dict.put(field, self._values[i]);
            }
            return dict;
        }

        /// _replace(**kwargs) - Return new instance with specified fields replaced
        pub fn _replace(self: Self, replacements: anytype) Self {
            var new_values = self._values;
            inline for (std.meta.fields(@TypeOf(replacements))) |field| {
                const idx = self.fieldIndex(field.name);
                if (idx) |i| {
                    new_values[i] = @field(replacements, field.name);
                }
            }
            return .{
                ._fields = self._fields,
                ._values = new_values,
                ._typename = self._typename,
            };
        }

        /// _make(iterable) - Make a new instance from existing sequence/iterable
        pub fn _make(typename: []const u8, field_names: [field_count][]const u8, values: []const i64) !Self {
            if (values.len != field_count) return error.ValueError;
            var arr: [field_count]i64 = undefined;
            for (values, 0..) |v, i| {
                arr[i] = v;
            }
            return Self.init(typename, field_names, arr);
        }

        /// __len__ - Return number of fields
        pub fn len(_: Self) usize {
            return field_count;
        }

        /// __iter__ - Iterate over values (for tuple iteration)
        pub fn iter(self: *const Self) NamedTupleIterator {
            return NamedTupleIterator.init(self);
        }

        const NamedTupleIterator = struct {
            nt: *const Self,
            index: usize,

            fn init(nt: *const Self) NamedTupleIterator {
                return .{ .nt = nt, .index = 0 };
            }

            pub fn next(it: *NamedTupleIterator) ?i64 {
                if (it.index >= field_count) return null;
                const value = it.nt._values[it.index];
                it.index += 1;
                return value;
            }
        };

        /// __eq__ - Compare two namedtuples
        pub fn eql(self: Self, other: Self) bool {
            if (!std.mem.eql(u8, self._typename, other._typename)) return false;
            for (self._values, 0..) |v, i| {
                if (v != other._values[i]) return false;
            }
            return true;
        }

        /// __hash__ - Hash the namedtuple (based on values)
        pub fn hash(self: Self) u64 {
            var h: u64 = 0;
            for (self._values) |v| {
                h = h *% 31 +% @as(u64, @bitCast(v));
            }
            return h;
        }

        /// _fields - Return tuple of field names
        pub fn fields(self: Self) [field_count][]const u8 {
            return self._fields;
        }

        /// _field_defaults - Return dict of default values (empty for base)
        pub fn _field_defaults(_: Self) std.StringHashMap(i64) {
            return std.StringHashMap(i64).init(std.heap.page_allocator);
        }
    };
}

/// Helper to create a namedtuple factory at comptime
/// Usage: const Point = namedtupleFactory("Point", .{"x", "y"});
pub fn namedtupleFactory(comptime typename: []const u8, comptime field_names: anytype) type {
    const field_count = field_names.len;

    return struct {
        data: NamedTuple(field_count),

        const Self = @This();
        pub const _typename = typename;
        pub const _fields = field_names;

        pub fn init(values: [field_count]i64) Self {
            return .{
                .data = NamedTuple(field_count).init(typename, field_names, values),
            };
        }

        pub fn get(self: Self, index: usize) ?i64 {
            return self.data.get(index);
        }

        pub fn getByName(self: Self, name: []const u8) ?i64 {
            return self.data.getByName(name);
        }

        pub fn _asdict(self: Self, allocator: Allocator) !std.StringHashMap(i64) {
            return self.data._asdict(allocator);
        }

        pub fn len(_: Self) usize {
            return field_count;
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.data.eql(other.data);
        }
    };
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
    try std.testing.expectEqual(@as(?i32, 2), d.get(0)); // 1 was evicted
}

test "counter basic" {
    const allocator = std.testing.allocator;
    var c = Counter(i32).init(allocator);
    defer c.deinit();

    try c.increment(1);
    try c.increment(1);
    try c.increment(2);

    try std.testing.expectEqual(@as(i64, 2), c.get(1));
    try std.testing.expectEqual(@as(i64, 1), c.get(2));
    try std.testing.expectEqual(@as(i64, 0), c.get(3));
    try std.testing.expectEqual(@as(i64, 3), c.total());
}

test "counter arithmetic" {
    const allocator = std.testing.allocator;
    var c1 = Counter(i32).init(allocator);
    defer c1.deinit();
    var c2 = Counter(i32).init(allocator);
    defer c2.deinit();

    try c1.set(1, 3);
    try c1.set(2, 1);
    try c2.set(1, 1);
    try c2.set(2, 2);
    try c2.set(3, 1);

    // Addition
    var sum = try c1.add(c2, allocator);
    defer sum.deinit();
    try std.testing.expectEqual(@as(i64, 4), sum.get(1)); // 3 + 1
    try std.testing.expectEqual(@as(i64, 3), sum.get(2)); // 1 + 2
    try std.testing.expectEqual(@as(i64, 1), sum.get(3)); // 0 + 1

    // Subtraction
    var diff = try c1.sub(c2, allocator);
    defer diff.deinit();
    try std.testing.expectEqual(@as(i64, 2), diff.get(1)); // 3 - 1 = 2
    try std.testing.expectEqual(@as(i64, 0), diff.get(2)); // 1 - 2 = -1, not kept

    // Intersection (min)
    var inter = try c1.intersection(c2, allocator);
    defer inter.deinit();
    try std.testing.expectEqual(@as(i64, 1), inter.get(1)); // min(3, 1)
    try std.testing.expectEqual(@as(i64, 1), inter.get(2)); // min(1, 2)
    try std.testing.expectEqual(@as(i64, 0), inter.get(3)); // min(0, 1) = 0

    // Union (max)
    var uni = try c1.@"union"(c2, allocator);
    defer uni.deinit();
    try std.testing.expectEqual(@as(i64, 3), uni.get(1)); // max(3, 1)
    try std.testing.expectEqual(@as(i64, 2), uni.get(2)); // max(1, 2)
    try std.testing.expectEqual(@as(i64, 1), uni.get(3)); // max(0, 1)
}

test "defaultdict" {
    const allocator = std.testing.allocator;

    const zero_factory = struct {
        fn f() i32 {
            return 0;
        }
    }.f;

    var dd = DefaultDict(i32, i32).initWithFactory(allocator, &zero_factory);
    defer dd.deinit();

    _ = try dd.get(1); // Creates default 0
    try dd.put(1, 10);

    try std.testing.expectEqual(@as(i32, 10), (try dd.get(1)));
    try std.testing.expectEqual(@as(i32, 0), (try dd.get(2))); // New key gets default
}

test "ordereddict" {
    const allocator = std.testing.allocator;
    var od = OrderedDict(i32, i32).init(allocator);
    defer od.deinit();

    try od.put(3, 30);
    try od.put(1, 10);
    try od.put(2, 20);

    const order = od.keys();
    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqual(@as(i32, 3), order[0]);
    try std.testing.expectEqual(@as(i32, 1), order[1]);
    try std.testing.expectEqual(@as(i32, 2), order[2]);

    // move_to_end
    try od.move_to_end(3, true); // move 3 to end
    const order2 = od.keys();
    try std.testing.expectEqual(@as(i32, 1), order2[0]);
    try std.testing.expectEqual(@as(i32, 2), order2[1]);
    try std.testing.expectEqual(@as(i32, 3), order2[2]);
}

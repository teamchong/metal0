/// Counter - Dict subclass for counting hashable objects
const std = @import("std");
const Allocator = std.mem.Allocator;

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
            var it1 = self.counts.iterator();
            while (it1.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const new_count = entry.value_ptr.* + other_count;
                if (new_count > 0) {
                    try result.counts.put(entry.key_ptr.*, new_count);
                }
            }
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
            var it1 = self.counts.iterator();
            while (it1.next()) |entry| {
                const other_count = other.get(entry.key_ptr.*);
                const max_count = @max(entry.value_ptr.*, other_count);
                if (max_count > 0) {
                    try result.counts.put(entry.key_ptr.*, max_count);
                }
            }
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

/// Count elements from iterable into mapping
pub fn _count_elements(comptime T: type, counter: *Counter(T), iterable: []const T) !void {
    for (iterable) |elem| {
        try counter.increment(elem);
    }
}

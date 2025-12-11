/// deque - Double-ended queue
const std = @import("std");
const Allocator = std.mem.Allocator;

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

        /// Rotate the deque n steps to the right (positive n) or left (negative n)
        /// Uses the efficient three-reversal algorithm: O(n) time, O(1) space
        pub fn rotate(self: *Self, n: i32) void {
            const item_count = self.items.items.len;
            if (item_count <= 1) return;

            // Normalize n to be within [0, item_count)
            const int_len: i32 = @intCast(item_count);
            const steps: usize = @intCast(@mod(@mod(n, int_len) + int_len, int_len));

            if (steps == 0) return;

            // Rotate right by `steps` using three-reversal algorithm:
            // [a, b, c, d, e] rotate 2 -> [d, e, a, b, c]
            // 1. Reverse entire array: [e, d, c, b, a]
            // 2. Reverse first `steps`: [d, e, c, b, a]
            // 3. Reverse rest: [d, e, a, b, c]
            const items = self.items.items;

            // Reverse helper for in-place range reversal
            const reverseRange = struct {
                fn do(slice: []T, start: usize, end: usize) void {
                    var i = start;
                    var j = end;
                    while (i < j) {
                        const tmp = slice[i];
                        slice[i] = slice[j];
                        slice[j] = tmp;
                        i += 1;
                        j -= 1;
                    }
                }
            }.do;

            // Three reversals for efficient in-place rotation
            reverseRange(items, 0, item_count - 1); // Reverse all
            reverseRange(items, 0, steps - 1); // Reverse first `steps`
            reverseRange(items, steps, item_count - 1); // Reverse rest
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
        /// index(x[, start[, stop]]) - search within [start, stop)
        pub fn index(self: Self, value: T) ?usize {
            return self.indexRange(value, 0, null);
        }

        /// index with start parameter
        pub fn indexStart(self: Self, value: T, start: usize) ?usize {
            return self.indexRange(value, start, null);
        }

        /// index with start and stop parameters
        pub fn indexRange(self: Self, value: T, start: usize, stop: ?usize) ?usize {
            const items_len = self.items.items.len;
            const actual_start = @min(start, items_len);
            const actual_stop = if (stop) |s| @min(s, items_len) else items_len;

            if (actual_start >= actual_stop) return null;

            for (self.items.items[actual_start..actual_stop], actual_start..) |item, i| {
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

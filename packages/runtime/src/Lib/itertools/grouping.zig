/// Grouping Iterators - groupby, starmap, batched
const std = @import("std");

// ============================================================================
// Grouping Iterator
// ============================================================================

/// groupby(iterable, key=None) - Make an iterator that returns consecutive keys and groups
/// Groups consecutive elements with the same key together
pub fn GroupByIterator(comptime T: type, comptime K: type) type {
    return struct {
        data: []const T,
        key_fn: *const fn (T) K,
        index: usize,
        current_key: ?K,

        const Self = @This();

        /// Group of consecutive elements with the same key
        pub const Group = struct {
            key: K,
            items: []const T,
        };

        pub fn init(data: []const T, key_fn: *const fn (T) K) Self {
            return .{
                .data = data,
                .key_fn = key_fn,
                .index = 0,
                .current_key = null,
            };
        }

        pub fn next(self: *Self, allocator: std.mem.Allocator) !?Group {
            if (self.index >= self.data.len) return null;

            // Get the key for current element
            const start_idx = self.index;
            const key = self.key_fn(self.data[self.index]);
            self.current_key = key;
            self.index += 1;

            // Collect all consecutive elements with same key
            while (self.index < self.data.len) {
                const next_key = self.key_fn(self.data[self.index]);
                if (!keysEqual(key, next_key)) break;
                self.index += 1;
            }

            // Return the group
            _ = allocator; // Not needed since we return slice of original data
            return Group{
                .key = key,
                .items = self.data[start_idx..self.index],
            };
        }

        fn keysEqual(a: K, b: K) bool {
            // For simple types, use == comparison
            // For more complex types, this would need custom equality
            return a == b;
        }
    };
}

/// groupby(iterable, key=None) - convenience function
/// key_fn: function that extracts the key from each element
pub fn groupby(comptime T: type, comptime K: type, data: []const T, key_fn: *const fn (T) K) GroupByIterator(T, K) {
    return GroupByIterator(T, K).init(data, key_fn);
}

/// Identity key function - group by element itself
pub fn identity(comptime T: type) fn (T) T {
    return struct {
        fn f(x: T) T {
            return x;
        }
    }.f;
}

/// StarMap iterator - itertools.starmap(func, iterable)
/// Calls func with arguments unpacked from tuples in iterable
pub fn StarMapIterator(comptime T: type, comptime R: type, comptime N: usize) type {
    return struct {
        data: []const [N]T,
        func: *const fn ([N]T) R,
        index: usize,

        const Self = @This();

        pub fn init(data: []const [N]T, func: *const fn ([N]T) R) Self {
            return .{ .data = data, .func = func, .index = 0 };
        }

        pub fn next(self: *Self) ?R {
            if (self.index >= self.data.len) return null;
            const result = self.func(self.data[self.index]);
            self.index += 1;
            return result;
        }
    };
}

/// starmap(func, iterable) - convenience function
pub fn starmap(comptime T: type, comptime R: type, comptime N: usize, data: []const [N]T, func: *const fn ([N]T) R) StarMapIterator(T, R, N) {
    return StarMapIterator(T, R, N).init(data, func);
}

/// batched(iterable, n) - Batch data into tuples of length n (Python 3.12+)
pub fn BatchedIterator(comptime T: type, comptime N: usize) type {
    return struct {
        data: []const T,
        index: usize,

        const Self = @This();

        pub fn init(data: []const T) Self {
            return .{ .data = data, .index = 0 };
        }

        pub fn next(self: *Self) ?[N]T {
            if (self.index + N > self.data.len) return null;
            var result: [N]T = undefined;
            for (0..N) |i| {
                result[i] = self.data[self.index + i];
            }
            self.index += N;
            return result;
        }
    };
}

/// batched(iterable, n) - convenience function
pub fn batched(comptime T: type, comptime N: usize, data: []const T) BatchedIterator(T, N) {
    return BatchedIterator(T, N).init(data);
}

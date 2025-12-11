/// Terminating Iterators - iterators that stop on shortest input
const std = @import("std");

// ============================================================================
// Iterators Terminating on Shortest Input
// ============================================================================

/// accumulate(iterable, func=operator.add, initial=None)
pub fn AccumulateIterator(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize,
        accumulator: ?T,
        func: *const fn (T, T) T,
        started: bool,

        const Self = @This();

        pub fn init(data: []const T, func: *const fn (T, T) T, initial: ?T) Self {
            return .{
                .data = data,
                .index = 0,
                .accumulator = initial orelse if (data.len > 0) data[0] else null,
                .func = func,
                .started = initial != null,
            };
        }

        pub fn next(self: *Self) ?T {
            if (!self.started) {
                if (self.data.len == 0) return null;
                self.started = true;
                self.index = 1;
                return self.accumulator;
            }

            if (self.index >= self.data.len) return null;
            const acc = self.accumulator orelse return null;

            self.accumulator = self.func(acc, self.data[self.index]);
            self.index += 1;
            return self.accumulator;
        }
    };
}

/// chain(*iterables) - Make an iterator that returns elements from multiple iterables
pub fn ChainIterator(comptime T: type) type {
    return struct {
        iterables: []const []const T,
        iter_index: usize,
        elem_index: usize,

        const Self = @This();

        pub fn init(iterables: []const []const T) Self {
            return .{ .iterables = iterables, .iter_index = 0, .elem_index = 0 };
        }

        pub fn next(self: *Self) ?T {
            while (self.iter_index < self.iterables.len) {
                const current = self.iterables[self.iter_index];
                if (self.elem_index < current.len) {
                    const result = current[self.elem_index];
                    self.elem_index += 1;
                    return result;
                }
                self.iter_index += 1;
                self.elem_index = 0;
            }
            return null;
        }
    };
}

/// chain(*iterables) - convenience function
pub fn chain(comptime T: type, iterables: []const []const T) ChainIterator(T) {
    return ChainIterator(T).init(iterables);
}

/// chain.from_iterable(iterable) - Alternate constructor for chain
/// Gets chained inputs from a single iterable argument that is evaluated lazily.
/// Equivalent to: chain(*iterable)
///
/// Example: chain.from_iterable(['ABC', 'DEF']) --> A B C D E F
pub fn chainFromIterable(comptime T: type, iterables: []const []const T) ChainIterator(T) {
    // In Zig with comptime slices, this is identical to chain()
    // The difference in Python is lazy evaluation of the outer iterable
    return ChainIterator(T).init(iterables);
}

/// ChainFromIterableIterator - Lazy version that pulls from outer iterator
pub fn ChainFromIterableIterator(comptime T: type, comptime OuterIterator: type) type {
    return struct {
        outer: OuterIterator,
        current_inner: ?[]const T,
        inner_index: usize,

        const Self = @This();

        pub fn init(outer: OuterIterator) Self {
            return .{ .outer = outer, .current_inner = null, .inner_index = 0 };
        }

        pub fn next(self: *Self) ?T {
            while (true) {
                // If we have a current inner iterable, get next from it
                if (self.current_inner) |inner| {
                    if (self.inner_index < inner.len) {
                        const result = inner[self.inner_index];
                        self.inner_index += 1;
                        return result;
                    }
                    // Inner exhausted, need new one
                    self.current_inner = null;
                    self.inner_index = 0;
                }

                // Get next inner iterable from outer
                if (self.outer.next()) |inner| {
                    self.current_inner = inner;
                    self.inner_index = 0;
                } else {
                    return null;
                }
            }
        }
    };
}

/// compress(data, selectors) - Make an iterator that filters elements from data
pub fn CompressIterator(comptime T: type) type {
    return struct {
        data: []const T,
        selectors: []const bool,
        index: usize,

        const Self = @This();

        pub fn init(data: []const T, selectors: []const bool) Self {
            return .{ .data = data, .selectors = selectors, .index = 0 };
        }

        pub fn next(self: *Self) ?T {
            while (self.index < self.data.len and self.index < self.selectors.len) {
                const idx = self.index;
                self.index += 1;
                if (self.selectors[idx]) {
                    return self.data[idx];
                }
            }
            return null;
        }
    };
}

/// compress(data, selectors) - convenience function
pub fn compress(comptime T: type, data: []const T, selectors: []const bool) CompressIterator(T) {
    return CompressIterator(T).init(data, selectors);
}

/// dropwhile(predicate, iterable) - Drop items while predicate is true
pub fn DropWhileIterator(comptime T: type) type {
    return struct {
        data: []const T,
        predicate: *const fn (T) bool,
        index: usize,
        dropping: bool,

        const Self = @This();

        pub fn init(data: []const T, predicate: *const fn (T) bool) Self {
            return .{ .data = data, .predicate = predicate, .index = 0, .dropping = true };
        }

        pub fn next(self: *Self) ?T {
            while (self.index < self.data.len) {
                const item = self.data[self.index];
                self.index += 1;

                if (self.dropping) {
                    if (!self.predicate(item)) {
                        self.dropping = false;
                        return item;
                    }
                } else {
                    return item;
                }
            }
            return null;
        }
    };
}

/// dropwhile(predicate, iterable) - convenience function
pub fn dropwhile(comptime T: type, data: []const T, predicate: *const fn (T) bool) DropWhileIterator(T) {
    return DropWhileIterator(T).init(data, predicate);
}

/// filterfalse(predicate, iterable) - Return items where predicate is false
pub fn FilterFalseIterator(comptime T: type) type {
    return struct {
        data: []const T,
        predicate: *const fn (T) bool,
        index: usize,

        const Self = @This();

        pub fn init(data: []const T, predicate: *const fn (T) bool) Self {
            return .{ .data = data, .predicate = predicate, .index = 0 };
        }

        pub fn next(self: *Self) ?T {
            while (self.index < self.data.len) {
                const item = self.data[self.index];
                self.index += 1;
                if (!self.predicate(item)) {
                    return item;
                }
            }
            return null;
        }
    };
}

/// filterfalse(predicate, iterable) - convenience function
pub fn filterfalse(comptime T: type, data: []const T, predicate: *const fn (T) bool) FilterFalseIterator(T) {
    return FilterFalseIterator(T).init(data, predicate);
}

/// islice(iterable, stop) or islice(iterable, start, stop, step)
pub fn ISliceIterator(comptime T: type) type {
    return struct {
        data: []const T,
        start: usize,
        stop: usize,
        step: usize,
        current: usize,

        const Self = @This();

        pub fn init(data: []const T, start: usize, stop: usize, step: usize) Self {
            return .{
                .data = data,
                .start = start,
                .stop = stop,
                .step = if (step == 0) 1 else step,
                .current = start,
            };
        }

        pub fn next(self: *Self) ?T {
            if (self.current >= self.stop or self.current >= self.data.len) return null;
            const result = self.data[self.current];
            self.current += self.step;
            return result;
        }
    };
}

/// islice(iterable, stop) - convenience function
pub fn islice(comptime T: type, data: []const T, stop: usize) ISliceIterator(T) {
    return ISliceIterator(T).init(data, 0, stop, 1);
}

/// islice(iterable, start, stop, step) - convenience function with all params
pub fn isliceEx(comptime T: type, data: []const T, start: usize, stop: usize, step: usize) ISliceIterator(T) {
    return ISliceIterator(T).init(data, start, stop, step);
}

/// pairwise(iterable) - Return successive overlapping pairs
pub fn PairwiseIterator(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize,

        const Self = @This();

        pub fn init(data: []const T) Self {
            return .{ .data = data, .index = 0 };
        }

        pub fn next(self: *Self) ?struct { T, T } {
            if (self.index + 1 >= self.data.len) return null;
            const result = .{ self.data[self.index], self.data[self.index + 1] };
            self.index += 1;
            return result;
        }
    };
}

/// pairwise(iterable) - convenience function
pub fn pairwise(comptime T: type, data: []const T) PairwiseIterator(T) {
    return PairwiseIterator(T).init(data);
}

/// takewhile(predicate, iterable) - Return items while predicate is true
pub fn TakeWhileIterator(comptime T: type) type {
    return struct {
        data: []const T,
        predicate: *const fn (T) bool,
        index: usize,
        done: bool,

        const Self = @This();

        pub fn init(data: []const T, predicate: *const fn (T) bool) Self {
            return .{ .data = data, .predicate = predicate, .index = 0, .done = false };
        }

        pub fn next(self: *Self) ?T {
            if (self.done or self.index >= self.data.len) return null;
            const item = self.data[self.index];
            if (!self.predicate(item)) {
                self.done = true;
                return null;
            }
            self.index += 1;
            return item;
        }
    };
}

/// takewhile(predicate, iterable) - convenience function
pub fn takewhile(comptime T: type, data: []const T, predicate: *const fn (T) bool) TakeWhileIterator(T) {
    return TakeWhileIterator(T).init(data, predicate);
}

/// zip_longest(*iterables, fillvalue=None) - Make an iterator that aggregates elements
pub fn ZipLongestIterator(comptime T: type) type {
    return struct {
        iterables: []const []const T,
        index: usize,
        fillvalue: T,

        const Self = @This();

        pub fn init(iterables: []const []const T, fillvalue: T) Self {
            return .{ .iterables = iterables, .index = 0, .fillvalue = fillvalue };
        }

        pub fn next(self: *Self, allocator: std.mem.Allocator) !?[]T {
            // Check if all iterables are exhausted
            var any_remaining = false;
            for (self.iterables) |iter| {
                if (self.index < iter.len) {
                    any_remaining = true;
                    break;
                }
            }
            if (!any_remaining) return null;

            var result = try allocator.alloc(T, self.iterables.len);
            for (self.iterables, 0..) |iter, i| {
                result[i] = if (self.index < iter.len) iter[self.index] else self.fillvalue;
            }
            self.index += 1;
            return result;
        }
    };
}

/// zip_longest(*iterables, fillvalue=None) - convenience function
pub fn zip_longest(comptime T: type, iterables: []const []const T, fillvalue: T) ZipLongestIterator(T) {
    return ZipLongestIterator(T).init(iterables, fillvalue);
}

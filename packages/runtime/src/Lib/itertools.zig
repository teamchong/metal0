/// itertools module - Functions creating iterators for efficient looping
/// CPython Reference: https://docs.python.org/3.12/library/itertools.html
const std = @import("std");

// Reuse existing iterator infrastructure
const iterobject = @import("../Python/iterobject.zig");
pub const SequenceIterator = iterobject.SequenceIterator;

// ============================================================================
// Infinite Iterators
// ============================================================================

/// count(start=0, step=1) - Make an iterator that returns evenly spaced values
pub fn CountIterator(comptime T: type) type {
    return struct {
        current: T,
        step: T,

        const Self = @This();

        pub fn init(start: T, step: T) Self {
            return .{ .current = start, .step = step };
        }

        pub fn next(self: *Self) T {
            const result = self.current;
            self.current += self.step;
            return result;
        }
    };
}

/// count(start=0, step=1) - convenience function
pub fn count(comptime T: type, start: T, step: T) CountIterator(T) {
    return CountIterator(T).init(start, step);
}

/// cycle(iterable) - Make an iterator returning elements from the iterable and saving a copy
pub fn CycleIterator(comptime T: type) type {
    return struct {
        data: []const T,
        index: usize,

        const Self = @This();

        pub fn init(data: []const T) Self {
            return .{ .data = data, .index = 0 };
        }

        pub fn next(self: *Self) ?T {
            if (self.data.len == 0) return null;
            const result = self.data[self.index];
            self.index = (self.index + 1) % self.data.len;
            return result;
        }
    };
}

/// cycle(iterable) - convenience function
pub fn cycle(comptime T: type, data: []const T) CycleIterator(T) {
    return CycleIterator(T).init(data);
}

/// repeat(object, times=None) - Make an iterator that returns object over and over
pub fn RepeatIterator(comptime T: type) type {
    return struct {
        value: T,
        times: ?usize,
        count_val: usize,

        const Self = @This();

        pub fn init(value: T, times: ?usize) Self {
            return .{ .value = value, .times = times, .count_val = 0 };
        }

        pub fn next(self: *Self) ?T {
            if (self.times) |t| {
                if (self.count_val >= t) return null;
                self.count_val += 1;
            }
            return self.value;
        }
    };
}

/// repeat(object, times=None) - convenience function
pub fn repeat(comptime T: type, value: T, times: ?usize) RepeatIterator(T) {
    return RepeatIterator(T).init(value, times);
}

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

// ============================================================================
// Combinatoric Iterators
// ============================================================================

/// product(*iterables, repeat=1) - Cartesian product of input iterables
/// Returns all combinations as a flat iterator
pub fn ProductIterator(comptime T: type, comptime N: usize) type {
    return struct {
        iterables: [N][]const T,
        indices: [N]usize,
        done: bool,

        const Self = @This();

        pub fn init(iterables: [N][]const T) Self {
            var indices: [N]usize = undefined;
            for (&indices) |*idx| idx.* = 0;

            // Check if any iterable is empty
            var done = false;
            for (iterables) |iter| {
                if (iter.len == 0) {
                    done = true;
                    break;
                }
            }

            return .{ .iterables = iterables, .indices = indices, .done = done };
        }

        pub fn next(self: *Self) ?[N]T {
            if (self.done) return null;

            // Get current combination
            var result: [N]T = undefined;
            for (0..N) |i| {
                result[i] = self.iterables[i][self.indices[i]];
            }

            // Increment indices (like counting in mixed radix)
            var i: usize = N;
            while (i > 0) {
                i -= 1;
                self.indices[i] += 1;
                if (self.indices[i] < self.iterables[i].len) {
                    break;
                }
                self.indices[i] = 0;
                if (i == 0) {
                    self.done = true;
                }
            }

            return result;
        }
    };
}

/// permutations(iterable, r=None) - Return successive r-length permutations
pub fn PermutationsIterator(comptime T: type, comptime R: usize) type {
    return struct {
        data: []const T,
        indices: [R]usize,
        cycles: [R]usize,
        done: bool,

        const Self = @This();

        pub fn init(data: []const T) Self {
            const n = data.len;
            var indices: [R]usize = undefined;
            var cycles: [R]usize = undefined;

            if (R > n) {
                return .{ .data = data, .indices = indices, .cycles = cycles, .done = true };
            }

            for (0..R) |i| {
                indices[i] = i;
                cycles[i] = n - i;
            }

            return .{ .data = data, .indices = indices, .cycles = cycles, .done = false };
        }

        pub fn next(self: *Self) ?[R]T {
            if (self.done) return null;

            // Get current permutation
            var result: [R]T = undefined;
            for (0..R) |i| {
                result[i] = self.data[self.indices[i]];
            }

            // Generate next permutation
            var i: usize = R;
            while (i > 0) {
                i -= 1;
                self.cycles[i] -= 1;
                if (self.cycles[i] == 0) {
                    // Rotate indices[i:] left by 1
                    const temp = self.indices[i];
                    var j = i;
                    while (j + 1 < self.data.len and j + 1 < R + (self.data.len - R)) {
                        if (j + 1 < R) {
                            self.indices[j] = self.indices[j + 1];
                        }
                        j += 1;
                    }
                    if (i < R) {
                        self.indices[if (R > 1) R - 1 else 0] = temp;
                    }
                    self.cycles[i] = self.data.len - i;
                } else {
                    // Swap
                    const j = self.data.len - self.cycles[i];
                    const temp = self.indices[i];
                    self.indices[i] = if (j < R) self.indices[j] else j;
                    if (j < R) self.indices[j] = temp;
                    return result;
                }
            }

            self.done = true;
            return result;
        }
    };
}

/// combinations(iterable, r) - Return r-length combinations
pub fn CombinationsIterator(comptime T: type, comptime R: usize) type {
    return struct {
        data: []const T,
        indices: [R]usize,
        done: bool,

        const Self = @This();

        pub fn init(data: []const T) Self {
            var indices: [R]usize = undefined;

            if (R > data.len) {
                return .{ .data = data, .indices = indices, .done = true };
            }

            for (0..R) |i| {
                indices[i] = i;
            }

            return .{ .data = data, .indices = indices, .done = false };
        }

        pub fn next(self: *Self) ?[R]T {
            if (self.done) return null;

            // Get current combination
            var result: [R]T = undefined;
            for (0..R) |i| {
                result[i] = self.data[self.indices[i]];
            }

            // Generate next combination
            var i: usize = R;
            while (i > 0) {
                i -= 1;
                if (self.indices[i] != i + self.data.len - R) {
                    self.indices[i] += 1;
                    for (i + 1..R) |j| {
                        self.indices[j] = self.indices[j - 1] + 1;
                    }
                    return result;
                }
            }

            self.done = true;
            return result;
        }
    };
}

// ============================================================================
// Convenience functions to collect iterator results
// ============================================================================

/// Collect all elements from an iterator into a slice
pub fn collect(comptime T: type, comptime Iter: type, iter: *Iter, allocator: std.mem.Allocator) ![]T {
    var result = std.ArrayList(T).init(allocator);
    while (iter.next()) |item| {
        try result.append(item);
    }
    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "count iterator" {
    var c = count(i32, 10, 2);
    try std.testing.expectEqual(@as(i32, 10), c.next());
    try std.testing.expectEqual(@as(i32, 12), c.next());
    try std.testing.expectEqual(@as(i32, 14), c.next());
}

test "cycle iterator" {
    var cyc = cycle(i32, &[_]i32{ 1, 2, 3 });
    try std.testing.expectEqual(@as(?i32, 1), cyc.next());
    try std.testing.expectEqual(@as(?i32, 2), cyc.next());
    try std.testing.expectEqual(@as(?i32, 3), cyc.next());
    try std.testing.expectEqual(@as(?i32, 1), cyc.next());
}

test "repeat iterator" {
    var r = repeat(i32, 42, 3);
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, 42), r.next());
    try std.testing.expectEqual(@as(?i32, null), r.next());
}

test "chain iterator" {
    const a = [_]i32{ 1, 2 };
    const b = [_]i32{ 3, 4, 5 };
    var ch = chain(i32, &[_][]const i32{ &a, &b });
    try std.testing.expectEqual(@as(?i32, 1), ch.next());
    try std.testing.expectEqual(@as(?i32, 2), ch.next());
    try std.testing.expectEqual(@as(?i32, 3), ch.next());
    try std.testing.expectEqual(@as(?i32, 4), ch.next());
    try std.testing.expectEqual(@as(?i32, 5), ch.next());
    try std.testing.expectEqual(@as(?i32, null), ch.next());
}

test "islice iterator" {
    const data = [_]i32{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var sl = islice(i32, &data, 5);
    try std.testing.expectEqual(@as(?i32, 0), sl.next());
    try std.testing.expectEqual(@as(?i32, 1), sl.next());
    try std.testing.expectEqual(@as(?i32, 2), sl.next());
    try std.testing.expectEqual(@as(?i32, 3), sl.next());
    try std.testing.expectEqual(@as(?i32, 4), sl.next());
    try std.testing.expectEqual(@as(?i32, null), sl.next());
}

test "pairwise iterator" {
    const data = [_]i32{ 1, 2, 3, 4 };
    var pw = pairwise(i32, &data);
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 1, 2 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 2, 3 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, .{ 3, 4 }), pw.next());
    try std.testing.expectEqual(@as(?struct { i32, i32 }, null), pw.next());
}

test "combinations iterator" {
    const data = [_]i32{ 1, 2, 3, 4 };
    var comb = CombinationsIterator(i32, 2).init(&data);

    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 2 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 3 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 1, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 2, 3 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 2, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, .{ 3, 4 }), comb.next());
    try std.testing.expectEqual(@as(?[2]i32, null), comb.next());
}

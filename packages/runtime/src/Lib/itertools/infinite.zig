/// Infinite Iterators - iterators that produce values indefinitely
const std = @import("std");

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

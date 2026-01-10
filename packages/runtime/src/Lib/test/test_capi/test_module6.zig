//! test.test_capi.test_module6 - C API Module Tests Part 6 - Iteration Protocol
const std = @import("std");

/// Iterator protocol implementation
pub const PyIter = struct {
    index: usize = 0,
    length: usize,
    items: []const Item,

    pub const Item = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
    };

    pub fn init(items: []const Item) PyIter {
        return .{ .length = items.len, .items = items };
    }

    pub fn next(self: *PyIter) ?Item {
        if (self.index < self.length) {
            const item = self.items[self.index];
            self.index += 1;
            return item;
        }
        return null;
    }

    pub fn reset(self: *PyIter) void {
        self.index = 0;
    }

    pub fn remaining(self: *const PyIter) usize {
        return self.length - self.index;
    }
};

/// Generator-like iterator
pub fn Generator(comptime T: type) type {
    return struct {
        state: T,
        step_fn: *const fn (*T) ?T,

        const Self = @This();

        pub fn init(initial: T, step_fn: *const fn (*T) ?T) Self {
            return .{ .state = initial, .step_fn = step_fn };
        }

        pub fn next(self: *Self) ?T {
            return self.step_fn(&self.state);
        }
    };
}

/// Range iterator
pub const RangeIter = struct {
    current: i64,
    stop: i64,
    step: i64,

    pub fn init(start: i64, stop: i64, step: i64) RangeIter {
        return .{ .current = start, .stop = stop, .step = step };
    }

    pub fn next(self: *RangeIter) ?i64 {
        if (self.step > 0 and self.current >= self.stop) return null;
        if (self.step < 0 and self.current <= self.stop) return null;

        const value = self.current;
        self.current += self.step;
        return value;
    }

    pub fn len(self: *const RangeIter) usize {
        if (self.step > 0) {
            if (self.current >= self.stop) return 0;
            return @intCast(@divFloor(self.stop - self.current + self.step - 1, self.step));
        } else {
            if (self.current <= self.stop) return 0;
            return @intCast(@divFloor(self.current - self.stop - self.step - 1, -self.step));
        }
    }
};

/// Enumerate iterator
pub fn EnumerateIter(comptime T: type) type {
    return struct {
        iter: *T,
        index: usize = 0,

        const Self = @This();

        pub fn init(iter: *T) Self {
            return .{ .iter = iter };
        }

        pub fn next(self: *Self) ?struct { index: usize, value: @typeInfo(@TypeOf(self.iter.next())).optional.child } {
            if (self.iter.next()) |value| {
                const result = .{ .index = self.index, .value = value };
                self.index += 1;
                return result;
            }
            return null;
        }
    };
}

/// Zip iterator for two iterators
pub fn ZipIter(comptime A: type, comptime B: type) type {
    return struct {
        iter_a: *A,
        iter_b: *B,

        const Self = @This();

        pub fn init(iter_a: *A, iter_b: *B) Self {
            return .{ .iter_a = iter_a, .iter_b = iter_b };
        }

        pub fn next(self: *Self) ?struct { a: @typeInfo(@TypeOf(self.iter_a.next())).optional.child, b: @typeInfo(@TypeOf(self.iter_b.next())).optional.child } {
            const a = self.iter_a.next() orelse return null;
            const b = self.iter_b.next() orelse return null;
            return .{ .a = a, .b = b };
        }
    };
}

test "PyIter basic" {
    const items = [_]PyIter.Item{ .{ .int = 1 }, .{ .int = 2 }, .{ .int = 3 } };
    var iter = PyIter.init(&items);

    try std.testing.expectEqual(@as(usize, 3), iter.remaining());

    try std.testing.expectEqual(@as(i64, 1), iter.next().?.int);
    try std.testing.expectEqual(@as(i64, 2), iter.next().?.int);
    try std.testing.expectEqual(@as(i64, 3), iter.next().?.int);
    try std.testing.expect(iter.next() == null);
}

test "PyIter reset" {
    const items = [_]PyIter.Item{.{ .int = 42 }};
    var iter = PyIter.init(&items);

    _ = iter.next();
    try std.testing.expect(iter.next() == null);

    iter.reset();
    try std.testing.expectEqual(@as(i64, 42), iter.next().?.int);
}

test "RangeIter forward" {
    var range = RangeIter.init(0, 5, 1);

    try std.testing.expectEqual(@as(i64, 0), range.next().?);
    try std.testing.expectEqual(@as(i64, 1), range.next().?);
    try std.testing.expectEqual(@as(i64, 2), range.next().?);
    try std.testing.expectEqual(@as(i64, 3), range.next().?);
    try std.testing.expectEqual(@as(i64, 4), range.next().?);
    try std.testing.expect(range.next() == null);
}

test "RangeIter backward" {
    var range = RangeIter.init(5, 0, -1);

    try std.testing.expectEqual(@as(i64, 5), range.next().?);
    try std.testing.expectEqual(@as(i64, 4), range.next().?);
    try std.testing.expectEqual(@as(i64, 3), range.next().?);
    try std.testing.expectEqual(@as(i64, 2), range.next().?);
    try std.testing.expectEqual(@as(i64, 1), range.next().?);
    try std.testing.expect(range.next() == null);
}

test "RangeIter step" {
    var range = RangeIter.init(0, 10, 2);

    try std.testing.expectEqual(@as(i64, 0), range.next().?);
    try std.testing.expectEqual(@as(i64, 2), range.next().?);
    try std.testing.expectEqual(@as(i64, 4), range.next().?);
    try std.testing.expectEqual(@as(i64, 6), range.next().?);
    try std.testing.expectEqual(@as(i64, 8), range.next().?);
    try std.testing.expect(range.next() == null);
}

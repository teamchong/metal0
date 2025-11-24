/// Generic iterator implementation (comptime specialized)
///
/// Pattern: One iterator type, infinite specializations!
/// - PyListIter, PyTupleIter, PySetIter all use this
/// - PyDictKeyIter, PyDictValueIter, PyDictItemIter too
/// - Zero code duplication via comptime!

const std = @import("std");

/// Generic iterator (comptime specialized)
///
/// Config must provide:
/// - ContainerType: type
/// - ItemType: type
/// - getSize(container: ContainerType) usize
/// - getItem(container: ContainerType, index: usize) ?ItemType
pub fn IteratorImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        container: Config.ContainerType,
        index: usize,

        pub fn init(container: Config.ContainerType) Self {
            return Self{
                .container = container,
                .index = 0,
            };
        }

        pub fn next(self: *Self) ?Config.ItemType {
            if (self.index >= Config.getSize(self.container)) {
                return null;
            }

            const item = Config.getItem(self.container, self.index);
            self.index += 1;
            return item;
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        pub fn hasNext(self: *const Self) bool {
            return self.index < Config.getSize(self.container);
        }

        pub fn remaining(self: *const Self) usize {
            const size = Config.getSize(self.container);
            return if (self.index < size) size - self.index else 0;
        }
    };
}

/// Slice iterator config (for native slices)
pub fn SliceIterConfig(comptime T: type) type {
    return struct {
        pub const ContainerType = []const T;
        pub const ItemType = T;

        pub fn getSize(slice: []const T) usize {
            return slice.len;
        }

        pub fn getItem(slice: []const T, index: usize) ?T {
            if (index >= slice.len) return null;
            return slice[index];
        }
    };
}

/// Mutable slice iterator config
pub fn MutableSliceIterConfig(comptime T: type) type {
    return struct {
        pub const ContainerType = []T;
        pub const ItemType = *T;

        pub fn getSize(slice: []T) usize {
            return slice.len;
        }

        pub fn getItem(slice: []T, index: usize) ?*T {
            if (index >= slice.len) return null;
            return &slice[index];
        }
    };
}

/// Range iterator config (like Python's range())
pub const RangeIterConfig = struct {
    pub const Range = struct {
        start: isize,
        end: isize,
        step: isize,
    };

    pub const ContainerType = Range;
    pub const ItemType = isize;

    pub fn getSize(range: Range) usize {
        if (range.step == 0) return 0;
        if (range.step > 0) {
            if (range.start >= range.end) return 0;
            const diff: usize = @intCast(range.end - range.start);
            const step_u: usize = @intCast(range.step);
            return (diff + step_u - 1) / step_u;
        } else {
            if (range.start <= range.end) return 0;
            const diff: usize = @intCast(range.start - range.end);
            const step_u: usize = @intCast(-range.step);
            return (diff + step_u - 1) / step_u;
        }
    }

    pub fn getItem(range: Range, index: usize) ?isize {
        const size = getSize(range);
        if (index >= size) return null;
        return range.start + @as(isize, @intCast(index)) * range.step;
    }
};

// Convenience type aliases
pub const SliceIter = IteratorImpl(SliceIterConfig(u8));
pub const IntSliceIter = IteratorImpl(SliceIterConfig(i64));
pub const RangeIter = IteratorImpl(RangeIterConfig);

// Tests
test "slice iterator" {
    const testing = std.testing;

    const data = [_]i64{ 1, 2, 3, 4, 5 };
    const Config = SliceIterConfig(i64);
    const Iter = IteratorImpl(Config);

    var iter = Iter.init(&data);

    try testing.expectEqual(@as(?i64, 1), iter.next());
    try testing.expectEqual(@as(?i64, 2), iter.next());
    try testing.expectEqual(@as(?i64, 3), iter.next());
    try testing.expect(iter.hasNext());
    try testing.expectEqual(@as(usize, 2), iter.remaining());

    try testing.expectEqual(@as(?i64, 4), iter.next());
    try testing.expectEqual(@as(?i64, 5), iter.next());
    try testing.expectEqual(@as(?i64, null), iter.next());
    try testing.expect(!iter.hasNext());
}

test "mutable slice iterator" {
    const testing = std.testing;

    var data = [_]i64{ 1, 2, 3 };
    const Config = MutableSliceIterConfig(i64);
    const Iter = IteratorImpl(Config);

    var iter = Iter.init(&data);

    if (iter.next()) |ptr| {
        try testing.expectEqual(@as(i64, 1), ptr.*);
        ptr.* = 10;
    }

    try testing.expectEqual(@as(i64, 10), data[0]);
}

test "range iterator" {
    const testing = std.testing;

    const range = RangeIterConfig.Range{ .start = 0, .end = 10, .step = 2 };
    var iter = RangeIter.init(range);

    try testing.expectEqual(@as(?isize, 0), iter.next());
    try testing.expectEqual(@as(?isize, 2), iter.next());
    try testing.expectEqual(@as(?isize, 4), iter.next());
    try testing.expectEqual(@as(?isize, 6), iter.next());
    try testing.expectEqual(@as(?isize, 8), iter.next());
    try testing.expectEqual(@as(?isize, null), iter.next());
}

test "range iterator reverse" {
    const testing = std.testing;

    const range = RangeIterConfig.Range{ .start = 10, .end = 0, .step = -2 };
    var iter = RangeIter.init(range);

    try testing.expectEqual(@as(?isize, 10), iter.next());
    try testing.expectEqual(@as(?isize, 8), iter.next());
    try testing.expectEqual(@as(?isize, 6), iter.next());
    try testing.expectEqual(@as(?isize, 4), iter.next());
    try testing.expectEqual(@as(?isize, 2), iter.next());
    try testing.expectEqual(@as(?isize, null), iter.next());
}

test "iterator reset" {
    const testing = std.testing;

    const data = [_]i64{ 1, 2, 3 };
    const Config = SliceIterConfig(i64);
    const Iter = IteratorImpl(Config);

    var iter = Iter.init(&data);

    try testing.expectEqual(@as(?i64, 1), iter.next());
    try testing.expectEqual(@as(?i64, 2), iter.next());

    iter.reset();

    try testing.expectEqual(@as(?i64, 1), iter.next());
    try testing.expectEqual(@as(?i64, 2), iter.next());
    try testing.expectEqual(@as(?i64, 3), iter.next());
}

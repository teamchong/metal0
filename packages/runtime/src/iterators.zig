/// Python-compatible iterator types
/// Supports iter(), next(), reversed() with proper state tracking
const std = @import("std");

/// Generic sequence iterator for tuples, lists, and arrays
pub fn SequenceIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []const T,
        index: usize,
        reversed: bool,

        pub const __type_name__ = "iterator";

        pub fn init(data: []const T) Self {
            return .{
                .data = data,
                .index = 0,
                .reversed = false,
            };
        }

        pub fn initReversed(data: []const T) Self {
            return .{
                .data = data,
                .index = data.len,
                .reversed = true,
            };
        }

        pub fn next(self: *Self) !T {
            if (self.reversed) {
                if (self.index == 0) return error.StopIteration;
                self.index -= 1;
                return self.data[self.index];
            } else {
                if (self.index >= self.data.len) return error.StopIteration;
                const item = self.data[self.index];
                self.index += 1;
                return item;
            }
        }

        pub fn __next__(self: *Self) !T {
            return self.next();
        }

        /// Get remaining items as slice (for tuple(iter) / list(iter))
        pub fn remaining(self: *const Self) []const T {
            if (self.reversed) {
                return self.data[0..self.index];
            } else {
                return self.data[self.index..];
            }
        }

        /// Check if iterator has more items
        pub fn hasNext(self: *const Self) bool {
            if (self.reversed) {
                return self.index > 0;
            } else {
                return self.index < self.data.len;
            }
        }

        /// Reset iterator to beginning
        pub fn reset(self: *Self) void {
            if (self.reversed) {
                self.index = self.data.len;
            } else {
                self.index = 0;
            }
        }

        /// Get current position (for pickle serialization)
        pub fn getState(self: *const Self) usize {
            return self.index;
        }

        /// Set current position (for pickle deserialization)
        pub fn setState(self: *Self, index: usize) void {
            self.index = index;
        }

        /// Convert to type name string (for type() comparison)
        pub fn typeName(self: *const Self) []const u8 {
            _ = self;
            return if (Self.reversed) "reversed" else "iterator";
        }
    };
}

/// Tuple iterator - iterates over tuple elements
pub const TupleIterator = SequenceIterator(i64);

/// List iterator - iterates over list elements
pub const ListIterator = SequenceIterator(i64);

/// Reversed iterator - iterates in reverse
pub const ReversedIterator = struct {
    const Self = @This();

    data: []const i64,
    index: usize,

    pub const __type_name__ = "reversed";

    pub fn init(data: []const i64) Self {
        return .{
            .data = data,
            .index = data.len,
        };
    }

    pub fn next(self: *Self) !i64 {
        if (self.index == 0) return error.StopIteration;
        self.index -= 1;
        return self.data[self.index];
    }

    pub fn __next__(self: *Self) !i64 {
        return self.next();
    }

    pub fn remaining(self: *const Self) []const i64 {
        return self.data[0..self.index];
    }

    pub fn hasNext(self: *const Self) bool {
        return self.index > 0;
    }

    pub fn getState(self: *const Self) usize {
        return self.index;
    }

    pub fn setState(self: *Self, index: usize) void {
        self.index = index;
    }

    pub fn typeName(self: *const Self) []const u8 {
        _ = self;
        return "reversed";
    }
};

/// Anytype iterator for pickle compatibility
pub const AnyIterator = struct {
    const Self = @This();

    type_name: []const u8,
    // Store data as raw bytes for type erasure
    data_ptr: *anyopaque,
    data_len: usize,
    elem_size: usize,
    index: usize,
    reversed: bool,

    pub fn getTypeName(self: *const Self) []const u8 {
        return self.type_name;
    }

    pub fn getIndex(self: *const Self) usize {
        return self.index;
    }

    pub fn setIndex(self: *Self, idx: usize) void {
        self.index = idx;
    }
};

/// Create an iterator for a tuple/array
pub fn iter(comptime T: type, data: []const T) SequenceIterator(T) {
    return SequenceIterator(T).init(data);
}

/// Create a reversed iterator
pub fn reversed(comptime T: type, data: []const T) SequenceIterator(T) {
    return SequenceIterator(T).initReversed(data);
}

/// Get next item from any iterator type
pub fn nextItem(iter_ptr: anytype) !@typeInfo(@TypeOf(iter_ptr.*)).@"struct".fields[0].type {
    return iter_ptr.next();
}

// Tests
test "TupleIterator" {
    const data = [_]i64{ 1, 2, 3, 4 };
    var it = TupleIterator.init(&data);

    try std.testing.expectEqual(@as(i64, 1), try it.next());
    try std.testing.expectEqual(@as(i64, 2), try it.next());
    try std.testing.expectEqual(@as(i64, 3), try it.next());
    try std.testing.expectEqual(@as(i64, 4), try it.next());
    try std.testing.expectError(error.StopIteration, it.next());
}

test "ReversedIterator" {
    const data = [_]i64{ 1, 2, 3, 4 };
    var it = ReversedIterator.init(&data);

    try std.testing.expectEqual(@as(i64, 4), try it.next());
    try std.testing.expectEqual(@as(i64, 3), try it.next());
    try std.testing.expectEqual(@as(i64, 2), try it.next());
    try std.testing.expectEqual(@as(i64, 1), try it.next());
    try std.testing.expectError(error.StopIteration, it.next());
}

test "SequenceIterator remaining" {
    const data = [_]i64{ 1, 2, 3, 4 };
    var it = TupleIterator.init(&data);

    _ = try it.next();
    _ = try it.next();

    const rem = it.remaining();
    try std.testing.expectEqual(@as(usize, 2), rem.len);
    try std.testing.expectEqual(@as(i64, 3), rem[0]);
    try std.testing.expectEqual(@as(i64, 4), rem[1]);
}

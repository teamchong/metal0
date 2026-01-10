//! test.test_ctypes.test_arrays - Tests for ctypes arrays
//! Reference: cpython/Lib/test/test_ctypes/test_arrays.py

const std = @import("std");
const _support = @import("_support.zig");

pub fn Array(comptime T: type, comptime N: usize) type {
    return struct {
        const Self = @This();
        pub const ElementType = T;
        pub const length = N;

        items: [N]T = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.items, std.mem.zeroes(T));
            return self;
        }

        pub fn initWith(values: [N]T) Self {
            return .{ .items = values };
        }

        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= N) return null;
            return self.items[index];
        }

        pub fn set(self: *Self, index: usize, value: T) bool {
            if (index >= N) return false;
            self.items[index] = value;
            return true;
        }

        pub fn slice(self: *Self) []T { return &self.items; }
        pub fn len(_: *const Self) usize { return N; }
        pub fn sizeof() usize { return @sizeOf([N]T); }
    };
}

pub fn CharArray(comptime N: usize) type {
    return struct {
        const Self = @This();
        data: [N]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn fromString(s: []const u8) Self {
            var self = Self.init();
            const copy_len = @min(s.len, N - 1);
            @memcpy(self.data[0..copy_len], s[0..copy_len]);
            return self;
        }

        pub fn value(self: *const Self) []const u8 {
            var end: usize = 0;
            while (end < N and self.data[end] != 0) : (end += 1) {}
            return self.data[0..end];
        }
    };
}

pub const IntArray5 = Array(i32, 5);
pub const CharBuffer = CharArray(100);

test "int_array" {
    var arr = IntArray5.init();
    _ = arr.set(0, 42);
    try std.testing.expectEqual(@as(?i32, 42), arr.get(0));
}

test "char_array" {
    const buf = CharBuffer.fromString("Hello");
    try std.testing.expectEqualStrings("Hello", buf.value());
}

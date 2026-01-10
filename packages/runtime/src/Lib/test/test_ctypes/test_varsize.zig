//! test.test_ctypes.test_varsize - Tests for variable-sized ctypes structures
//! Reference: cpython/Lib/test/test_ctypes/test_varsize.py

const std = @import("std");

pub fn VarSizeArray(comptime T: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        data: []T,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            return .{ .allocator = allocator, .data = try allocator.alloc(T, size) };
        }
        pub fn deinit(self: *Self) void { self.allocator.free(self.data); }
        pub fn len(self: Self) usize { return self.data.len; }
        pub fn get(self: Self, i: usize) ?T { return if (i < self.data.len) self.data[i] else null; }
        pub fn set(self: *Self, i: usize, v: T) void { if (i < self.data.len) self.data[i] = v; }
    };
}

test "varsize_array" {
    var arr = try VarSizeArray(i32).init(std.testing.allocator, 10);
    defer arr.deinit();
    try std.testing.expectEqual(@as(usize, 10), arr.len());
    arr.set(0, 42);
    try std.testing.expectEqual(@as(?i32, 42), arr.get(0));
}

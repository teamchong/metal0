//! importlib.metadata._functools - Function utilities
//! Reference: cpython/Lib/importlib/metadata/_functools.py
//!
//! CPython exports: method_cache, pass_none

const std = @import("std");

/// passNone - Return None if input is None, otherwise apply function
/// CPython: def pass_none(func)
pub fn passNone(comptime T: type, comptime R: type, func: *const fn (T) R) *const fn (?T) ?R {
    const wrapper = struct {
        fn call(value: ?T) ?R {
            if (value) |v| {
                return func(v);
            }
            return null;
        }
    };
    return wrapper.call;
}

/// Simple cache for method results
pub fn MethodCache(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        data: std.AutoHashMap(K, V),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .data = std.AutoHashMap(K, V).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: *const Self, key: K) ?V {
            return self.data.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            try self.data.put(key, value);
        }

        pub fn clearCache(self: *Self) void {
            self.data.clearRetainingCapacity();
        }
    };
}

test "MethodCache" {
    const allocator = std.testing.allocator;
    var cache = MethodCache(i32, []const u8).init(allocator);
    defer cache.deinit();

    try cache.put(1, "one");
    try cache.put(2, "two");

    try std.testing.expectEqualStrings("one", cache.get(1).?);
    try std.testing.expectEqualStrings("two", cache.get(2).?);
}

//! UserDict - Wrapper around dict for easier subclassing
//!
//! Mirrors: CPython Lib/collections/__init__.py - UserDict

const std = @import("std");

/// Wrapper around dict for easier subclassing
pub fn UserDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        data: std.AutoHashMap(K, V),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .data = std.AutoHashMap(K, V).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: Self, key: K) ?V {
            return self.data.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            try self.data.put(key, value);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.data.contains(key);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.data.remove(key);
        }

        pub fn len(self: Self) usize {
            return self.data.count();
        }
    };
}

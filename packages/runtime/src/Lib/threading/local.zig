//! Thread-local storage
//!
//! CPython source: Lib/threading.py (local class)

const std = @import("std");

/// Thread-local storage
pub fn local(comptime T: type) type {
    return struct {
        const Storage = @This();

        data: std.Thread.LocalStorage(T),

        pub fn init() Storage {
            return .{ .data = .{} };
        }

        pub fn get(self: *Storage) ?*T {
            return self.data.get();
        }

        pub fn set(self: *Storage, value: T) void {
            self.data.set(value);
        }
    };
}

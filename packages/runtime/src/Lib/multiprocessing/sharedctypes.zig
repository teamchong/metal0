//! Shared memory ctypes - Value and Array
const std = @import("std");

/// A shared memory value
pub fn Value(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        mutex: std.Thread.Mutex,

        pub fn init(initial: T) Self {
            return .{
                .value = initial,
                .mutex = .{},
            };
        }

        pub fn get(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.value;
        }

        pub fn set(self: *Self, val: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.value = val;
        }

        /// Get with lock held (for read-modify-write)
        pub fn getLockedValue(self: *Self) *T {
            self.mutex.lock();
            return &self.value;
        }

        pub fn releaseLockedValue(self: *Self) void {
            self.mutex.unlock();
        }
    };
}

/// A shared memory array
pub fn Array(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        data: []T,
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const data = try allocator.alloc(T, size);
            return .{
                .allocator = allocator,
                .data = data,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn get(self: *Self, index: usize) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.data[index];
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.data[index] = value;
        }

        pub fn len(self: *Self) usize {
            return self.data.len;
        }

        /// Get slice with lock held
        pub fn getLockedSlice(self: *Self) []T {
            self.mutex.lock();
            return self.data;
        }

        pub fn releaseLockedSlice(self: *Self) void {
            self.mutex.unlock();
        }
    };
}

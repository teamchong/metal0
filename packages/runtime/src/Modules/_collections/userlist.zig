/// UserList - Wrapper around list for easier subclassing
const std = @import("std");
const Allocator = std.mem.Allocator;

/// UserList - A wrapper around list objects for easier subclassing
pub fn UserList(comptime T: type) type {
    return struct {
        data: std.ArrayList(T),
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .data = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn append(self: *Self, value: T) !void {
            try self.data.append(self.allocator, value);
        }

        pub fn extend(self: *Self, values: []const T) !void {
            try self.data.appendSlice(self.allocator, values);
        }

        pub fn insert(self: *Self, idx: usize, value: T) !void {
            try self.data.insert(self.allocator, idx, value);
        }

        pub fn pop(self: *Self) ?T {
            return self.data.popOrNull();
        }

        pub fn remove(self: *Self, value: T) !void {
            for (self.data.items, 0..) |item, i| {
                if (item == value) {
                    _ = self.data.orderedRemove(i);
                    return;
                }
            }
            return error.ValueError;
        }

        pub fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
        }

        pub fn len(self: Self) usize {
            return self.data.items.len;
        }

        pub fn get(self: Self, idx: usize) ?T {
            if (idx >= self.data.items.len) return null;
            return self.data.items[idx];
        }

        pub fn set(self: *Self, idx: usize, value: T) !void {
            if (idx >= self.data.items.len) return error.IndexError;
            self.data.items[idx] = value;
        }

        pub fn index(self: Self, value: T) ?usize {
            for (self.data.items, 0..) |item, i| {
                if (item == value) return i;
            }
            return null;
        }

        pub fn count(self: Self, value: T) usize {
            var c: usize = 0;
            for (self.data.items) |item| {
                if (item == value) c += 1;
            }
            return c;
        }

        pub fn reverse(self: *Self) void {
            std.mem.reverse(T, self.data.items);
        }

        pub fn sort(self: *Self) void {
            std.mem.sort(T, self.data.items, {}, std.sort.asc(T));
        }

        pub fn copy(self: *Self) !Self {
            var new = Self.init(self.allocator);
            try new.data.appendSlice(self.allocator, self.data.items);
            return new;
        }

        pub fn items(self: Self) []const T {
            return self.data.items;
        }
    };
}

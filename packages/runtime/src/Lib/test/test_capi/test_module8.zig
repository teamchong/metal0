//! test.test_capi.test_module8 - C API Module Tests Part 8 - Sequence Protocol
const std = @import("std");

/// Sequence protocol implementation
pub fn Sequence(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .items = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn len(self: *const Self) usize {
            return self.items.items.len;
        }

        pub fn append(self: *Self, item: T) !void {
            try self.items.append(item);
        }

        pub fn getItem(self: *const Self, index: usize) !T {
            if (index >= self.items.items.len) return error.IndexError;
            return self.items.items[index];
        }

        pub fn setItem(self: *Self, index: usize, value: T) !void {
            if (index >= self.items.items.len) return error.IndexError;
            self.items.items[index] = value;
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items.items) |item| {
                if (item == value) return true;
            }
            return false;
        }

        pub fn index(self: *const Self, value: T) ?usize {
            for (self.items.items, 0..) |item, i| {
                if (item == value) return i;
            }
            return null;
        }

        pub fn count(self: *const Self, value: T) usize {
            var c: usize = 0;
            for (self.items.items) |item| {
                if (item == value) c += 1;
            }
            return c;
        }

        pub fn reverse(self: *Self) void {
            std.mem.reverse(T, self.items.items);
        }

        pub fn slice(self: *const Self, start: usize, end: usize) []const T {
            const s = @min(start, self.items.items.len);
            const e = @min(end, self.items.items.len);
            return self.items.items[s..e];
        }
    };
}

/// Tuple-like immutable sequence
pub fn Tuple(comptime N: usize, comptime T: type) type {
    return struct {
        items: [N]T,

        const Self = @This();

        pub fn init(items: [N]T) Self {
            return .{ .items = items };
        }

        pub fn len(self: *const Self) usize {
            _ = self;
            return N;
        }

        pub fn get(self: *const Self, index: usize) !T {
            if (index >= N) return error.IndexError;
            return self.items[index];
        }

        pub fn contains(self: *const Self, value: T) bool {
            for (self.items) |item| {
                if (item == value) return true;
            }
            return false;
        }
    };
}

/// Set-like sequence with unique elements
pub fn Set(comptime T: type) type {
    return struct {
        items: std.AutoHashMap(T, void),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .items = std.AutoHashMap(T, void).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn add(self: *Self, item: T) !void {
            try self.items.put(item, {});
        }

        pub fn remove(self: *Self, item: T) bool {
            return self.items.remove(item);
        }

        pub fn contains(self: *const Self, item: T) bool {
            return self.items.contains(item);
        }

        pub fn len(self: *const Self) usize {
            return self.items.count();
        }
    };
}

/// Concatenate two sequences
pub fn concat(comptime T: type, allocator: std.mem.Allocator, a: []const T, b: []const T) ![]T {
    const result = try allocator.alloc(T, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

/// Repeat sequence n times
pub fn repeat(comptime T: type, allocator: std.mem.Allocator, seq: []const T, n: usize) ![]T {
    const result = try allocator.alloc(T, seq.len * n);
    var offset: usize = 0;
    for (0..n) |_| {
        @memcpy(result[offset..][0..seq.len], seq);
        offset += seq.len;
    }
    return result;
}

test "Sequence basic operations" {
    const allocator = std.testing.allocator;
    var seq = Sequence(i32).init(allocator);
    defer seq.deinit();

    try seq.append(1);
    try seq.append(2);
    try seq.append(3);

    try std.testing.expectEqual(@as(usize, 3), seq.len());
    try std.testing.expectEqual(@as(i32, 2), try seq.getItem(1));
}

test "Sequence contains and index" {
    const allocator = std.testing.allocator;
    var seq = Sequence(i32).init(allocator);
    defer seq.deinit();

    try seq.append(10);
    try seq.append(20);
    try seq.append(30);

    try std.testing.expect(seq.contains(20));
    try std.testing.expect(!seq.contains(40));
    try std.testing.expectEqual(@as(usize, 1), seq.index(20).?);
}

test "Sequence reverse" {
    const allocator = std.testing.allocator;
    var seq = Sequence(i32).init(allocator);
    defer seq.deinit();

    try seq.append(1);
    try seq.append(2);
    try seq.append(3);

    seq.reverse();

    try std.testing.expectEqual(@as(i32, 3), try seq.getItem(0));
    try std.testing.expectEqual(@as(i32, 1), try seq.getItem(2));
}

test "Tuple" {
    const t = Tuple(3, i32).init(.{ 1, 2, 3 });

    try std.testing.expectEqual(@as(usize, 3), t.len());
    try std.testing.expectEqual(@as(i32, 2), try t.get(1));
    try std.testing.expect(t.contains(2));
}

test "Set" {
    const allocator = std.testing.allocator;
    var set = Set(i32).init(allocator);
    defer set.deinit();

    try set.add(1);
    try set.add(2);
    try set.add(1); // duplicate

    try std.testing.expectEqual(@as(usize, 2), set.len());
    try std.testing.expect(set.contains(1));
}

test "concat" {
    const allocator = std.testing.allocator;
    const a = [_]i32{ 1, 2 };
    const b = [_]i32{ 3, 4 };

    const result = try concat(i32, allocator, &a, &b);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(@as(i32, 3), result[2]);
}

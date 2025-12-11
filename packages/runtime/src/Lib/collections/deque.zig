//! deque - Double-ended queue
//!
//! Mirrors: CPython Lib/collections/__init__.py - deque

const std = @import("std");

/// Double-ended queue with O(1) append/pop on both ends
pub fn Deque(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            value: T,
            prev: ?*Node = null,
            next: ?*Node = null,
        };

        allocator: std.mem.Allocator,
        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,
        maxlen: ?usize = null,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn initMaxlen(allocator: std.mem.Allocator, maxlen: usize) Self {
            return .{ .allocator = allocator, .maxlen = maxlen };
        }

        pub fn deinit(self: *Self) void {
            self.clear();
        }

        /// Add to right end
        pub fn append(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .value = value, .prev = self.tail, .next = null };

            if (self.tail) |tail| {
                tail.next = node;
            } else {
                self.head = node;
            }
            self.tail = node;
            self.len += 1;

            // Enforce maxlen
            if (self.maxlen) |ml| {
                while (self.len > ml) {
                    _ = self.popleft() catch break;
                }
            }
        }

        /// Add to left end
        pub fn appendleft(self: *Self, value: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .value = value, .prev = null, .next = self.head };

            if (self.head) |head| {
                head.prev = node;
            } else {
                self.tail = node;
            }
            self.head = node;
            self.len += 1;

            // Enforce maxlen
            if (self.maxlen) |ml| {
                while (self.len > ml) {
                    _ = self.pop() catch break;
                }
            }
        }

        /// Remove and return from right end
        pub fn pop(self: *Self) !T {
            const node = self.tail orelse return error.Empty;
            const value = node.value;

            if (node.prev) |prev| {
                prev.next = null;
                self.tail = prev;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.allocator.destroy(node);
            self.len -= 1;
            return value;
        }

        /// Remove and return from left end
        pub fn popleft(self: *Self) !T {
            const node = self.head orelse return error.Empty;
            const value = node.value;

            if (node.next) |next| {
                next.prev = null;
                self.head = next;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.allocator.destroy(node);
            self.len -= 1;
            return value;
        }

        /// Extend right with iterable
        pub fn extend(self: *Self, items: []const T) !void {
            for (items) |item| {
                try self.append(item);
            }
        }

        /// Extend left with iterable
        pub fn extendleft(self: *Self, items: []const T) !void {
            for (items) |item| {
                try self.appendleft(item);
            }
        }

        /// Rotate n steps to the right
        pub fn rotate(self: *Self, n: i32) !void {
            if (self.len <= 1 or n == 0) return;

            const steps = @mod(n, @as(i32, @intCast(self.len)));
            if (steps == 0) return;

            if (steps > 0) {
                var i: i32 = 0;
                while (i < steps) : (i += 1) {
                    const val = try self.pop();
                    try self.appendleft(val);
                }
            } else {
                var i: i32 = 0;
                while (i < -steps) : (i += 1) {
                    const val = try self.popleft();
                    try self.append(val);
                }
            }
        }

        /// Remove all elements
        pub fn clear(self: *Self) void {
            while (self.head) |node| {
                self.head = node.next;
                self.allocator.destroy(node);
            }
            self.tail = null;
            self.len = 0;
        }

        /// Count occurrences of value
        pub fn count(self: Self, value: T) usize {
            var c: usize = 0;
            var node = self.head;
            while (node) |n| {
                if (n.value == value) c += 1;
                node = n.next;
            }
            return c;
        }

        /// Reverse in place
        pub fn reverse(self: *Self) void {
            var node = self.head;
            while (node) |n| {
                const tmp = n.prev;
                n.prev = n.next;
                n.next = tmp;
                node = n.prev; // Was next, now prev
            }
            const tmp = self.head;
            self.head = self.tail;
            self.tail = tmp;
        }

        /// Copy to new deque
        pub fn copy(self: Self, allocator: std.mem.Allocator) !Self {
            var result = Self.init(allocator);
            result.maxlen = self.maxlen;

            var node = self.head;
            while (node) |n| {
                try result.append(n.value);
                node = n.next;
            }
            return result;
        }

        /// Get item at index (negative indices supported)
        pub fn getItem(self: Self, index: i32) ?T {
            const actual_idx = if (index < 0)
                @as(usize, @intCast(@as(i32, @intCast(self.len)) + index))
            else
                @as(usize, @intCast(index));

            if (actual_idx >= self.len) return null;

            var node = self.head;
            var i: usize = 0;
            while (node) |n| {
                if (i == actual_idx) return n.value;
                node = n.next;
                i += 1;
            }
            return null;
        }
    };
}

test "Deque" {
    const allocator = std.testing.allocator;

    var dq = Deque(i32).init(allocator);
    defer dq.deinit();

    try dq.append(1);
    try dq.append(2);
    try dq.appendleft(0);

    try std.testing.expectEqual(@as(usize, 3), dq.len);
    try std.testing.expectEqual(@as(i32, 0), try dq.popleft());
    try std.testing.expectEqual(@as(i32, 2), try dq.pop());
}

test "Deque maxlen" {
    const allocator = std.testing.allocator;

    var dq = Deque(i32).initMaxlen(allocator, 3);
    defer dq.deinit();

    try dq.append(1);
    try dq.append(2);
    try dq.append(3);
    try dq.append(4); // Should remove 1

    try std.testing.expectEqual(@as(usize, 3), dq.len);
    try std.testing.expectEqual(@as(i32, 2), dq.getItem(0).?);
}

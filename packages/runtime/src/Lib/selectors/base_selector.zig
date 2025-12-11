//! Abstract base selector for I/O multiplexing.

const std = @import("std");
const types = @import("types.zig");

pub const SelectorKey = types.SelectorKey;
pub const EVENT_READ = types.EVENT_READ;
pub const EVENT_WRITE = types.EVENT_WRITE;

// ============================================================================
// BaseSelector
// ============================================================================

/// Abstract base class for selectors
pub const BaseSelector = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    registered: std.AutoHashMap(i32, SelectorKey),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .registered = std.AutoHashMap(i32, SelectorKey).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.registered.deinit();
    }

    /// Register a file object for monitoring
    pub fn register(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        if (self.registered.contains(fileobj)) {
            return error.KeyError;
        }

        const key = SelectorKey.init(fileobj, events, data);
        try self.registered.put(fileobj, key);
        return key;
    }

    /// Unregister a file object
    pub fn unregister(self: *Self, fileobj: i32) !SelectorKey {
        const key = self.registered.get(fileobj) orelse return error.KeyError;
        _ = self.registered.remove(fileobj);
        return key;
    }

    /// Modify the events for a registered file object
    pub fn modify(self: *Self, fileobj: i32, events: u32, data: ?*anyopaque) !SelectorKey {
        var key = self.registered.getPtr(fileobj) orelse return error.KeyError;
        key.events = events;
        key.data = data;
        return key.*;
    }

    /// Get the key for a file object
    pub fn getKey(self: *Self, fileobj: i32) !SelectorKey {
        return self.registered.get(fileobj) orelse error.KeyError;
    }

    /// Get a map of all registered file objects
    pub fn getMap(self: *Self) std.AutoHashMap(i32, SelectorKey) {
        return self.registered;
    }

    /// Close the selector
    pub fn close(self: *Self) void {
        self.registered.clearAndFree();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "BaseSelector init" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    try std.testing.expectEqual(@as(usize, 0), sel.registered.count());
}

test "BaseSelector register" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    const key = try sel.register(5, EVENT_READ, null);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(@as(usize, 1), sel.registered.count());
}

test "BaseSelector unregister" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    const key = try sel.unregister(5);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(@as(usize, 0), sel.registered.count());
}

test "BaseSelector modify" {
    const allocator = std.testing.allocator;
    var sel = BaseSelector.init(allocator);
    defer sel.deinit();

    _ = try sel.register(5, EVENT_READ, null);
    const key = try sel.modify(5, EVENT_WRITE, null);
    try std.testing.expectEqual(EVENT_WRITE, key.events);
}

/// Multi-interpreter queues module stub
/// Ported from CPython Lib/test/support/interpreters/queues.py
/// Provides inter-interpreter queue communication
const std = @import("std");

/// Queue for inter-interpreter communication
pub const Queue = struct {
    items: std.ArrayList(*anyopaque),
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*@This() {
        const queue = try allocator.create(@This());
        queue.* = .{
            .items = std.ArrayList(*anyopaque).init(allocator),
            .allocator = allocator,
        };
        return queue;
    }

    pub fn put(self: *@This(), obj: *anyopaque) !void {
        _ = self;
        _ = obj;
        return error.NotImplemented; // Stub
    }

    pub fn get(self: *@This()) !*anyopaque {
        _ = self;
        return error.NotImplemented; // Stub
    }

    pub fn close(self: *@This()) void {
        self.items.deinit();
    }
};

/// Create a new queue
pub fn create_queue(allocator: std.mem.Allocator) !*Queue {
    return Queue.create(allocator);
}

// DCE-friendly: Test-only module, unused in production

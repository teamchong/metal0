/// Channel for Inter-Interpreter Communication
/// Thread-safe message passing between interpreters

const std = @import("std");
const Allocator = std.mem.Allocator;
const data_mod = @import("data.zig");
const CrossInterpData = data_mod.CrossInterpData;

// ============================================================================
// Channel
// ============================================================================

/// Channel for inter-interpreter communication
pub const Channel = struct {
    const Self = @This();

    /// Channel ID
    id: u64,
    /// Message queue
    queue: std.ArrayList(CrossInterpData),
    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},
    /// Condition for blocking recv
    cond: std.Thread.Condition = .{},
    /// Is open for sending
    open: bool = true,
    /// Reference count
    refcount: u32 = 1,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u64) Self {
        return Self{
            .id = id,
            .queue = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.queue.items) |*item| {
            item.deinit();
        }
        self.queue.deinit(self.allocator);
    }

    /// Send data through the channel
    pub fn send(self: *Self, data: CrossInterpData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.open) {
            return error.ChannelClosed;
        }

        try self.queue.append(self.allocator, data);
        self.cond.signal();
    }

    /// Receive data from the channel (blocking)
    pub fn recv(self: *Self) ?CrossInterpData {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.queue.items.len == 0 and self.open) {
            self.cond.wait(&self.mutex);
        }

        if (self.queue.items.len == 0) {
            return null;
        }

        return self.queue.orderedRemove(0);
    }

    /// Try to receive without blocking
    pub fn tryRecv(self: *Self) ?CrossInterpData {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.items.len == 0) {
            return null;
        }

        return self.queue.orderedRemove(0);
    }

    /// Close the channel
    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.open = false;
        self.cond.broadcast();
    }

    /// Get queue length
    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.queue.items.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "channel" {
    const allocator = std.testing.allocator;
    var channel = Channel.init(allocator, 1);
    defer channel.deinit();

    const data = CrossInterpData.initInt(allocator, 42);
    try channel.send(data);

    try std.testing.expectEqual(@as(usize, 1), channel.len());

    const received = channel.tryRecv();
    try std.testing.expect(received != null);
    try std.testing.expectEqual(@as(i64, 42), received.?.data.int_val);
}

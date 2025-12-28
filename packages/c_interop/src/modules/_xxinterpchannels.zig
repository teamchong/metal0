//! Python '_xxinterpchannels' module - Inter-interpreter channels
//!
//! Low-level channel mechanism for passing data between interpreters.
//! Used by the `interpreters` module for inter-interpreter communication.
//!
//! In metal0's AOT model, channels provide thread-safe message passing
//! between execution contexts.
//!
//! Mirrors: CPython Modules/_xxinterpchannelsmodule.c

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const ChannelError = error{
    ChannelNotFound,
    ChannelClosed,
    ChannelEmpty,
    InvalidChannel,
    OutOfMemory,
    SendFailed,
    ReceiveFailed,
    Timeout,
};

// ============================================================================
// Types
// ============================================================================

pub const ChannelId = i64;

/// Channel end type
pub const ChannelEnd = enum {
    send,
    recv,
    both,
};

/// Message in a channel
pub const ChannelMessage = struct {
    data: []const u8,
    interpreter_id: i64,
};

/// Channel state
pub const Channel = struct {
    const Self = @This();

    id: ChannelId,
    allocator: std.mem.Allocator,
    queue: std.ArrayList(ChannelMessage) = .{},
    closed: bool = false,
    mutex: std.Thread.Mutex = .{},
    max_size: ?usize = null,

    pub fn init(alloc: std.mem.Allocator, id: ChannelId, max_size: ?usize) Self {
        return Self{
            .id = id,
            .allocator = alloc,
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free all queued messages
        for (self.queue.items) |msg| {
            self.allocator.free(msg.data);
        }
        self.queue.deinit(self.allocator);
    }

    pub fn send(self: *Self, data: []const u8, interp_id: i64) ChannelError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.closed) return error.ChannelClosed;

        if (self.max_size) |max| {
            if (self.queue.items.len >= max) {
                return error.SendFailed;
            }
        }

        // Copy data
        const copied = self.allocator.dupe(u8, data) catch return error.OutOfMemory;
        errdefer self.allocator.free(copied);

        self.queue.append(self.allocator, ChannelMessage{
            .data = copied,
            .interpreter_id = interp_id,
        }) catch return error.OutOfMemory;
    }

    pub fn recv(self: *Self) ChannelError!ChannelMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.queue.items.len == 0) {
            if (self.closed) return error.ChannelClosed;
            return error.ChannelEmpty;
        }

        return self.queue.orderedRemove(0);
    }

    pub fn close(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
    }

    pub fn isClosed(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.closed;
    }

    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.queue.items.len;
    }
};

// ============================================================================
// Channel Registry
// ============================================================================

const max_channels = 1024;
var channels: [max_channels]?*Channel = [_]?*Channel{null} ** max_channels;
var channel_count: usize = 0;
var next_channel_id: ChannelId = 1;
var allocator: std.mem.Allocator = std.heap.page_allocator;

// ============================================================================
// Functions
// ============================================================================

/// Create a new channel
pub fn create(max_size: ?usize) ChannelError!ChannelId {
    if (channel_count >= max_channels) {
        return error.OutOfMemory;
    }

    const id = next_channel_id;
    next_channel_id += 1;

    const channel = allocator.create(Channel) catch return error.OutOfMemory;
    channel.* = Channel.init(allocator, id, max_size);

    // Find empty slot
    for (&channels) |*slot| {
        if (slot.* == null) {
            slot.* = channel;
            channel_count += 1;
            return id;
        }
    }

    allocator.destroy(channel);
    return error.OutOfMemory;
}

/// Destroy a channel
pub fn destroy(id: ChannelId) ChannelError!void {
    for (&channels) |*slot| {
        if (slot.*) |channel| {
            if (channel.id == id) {
                channel.deinit();
                allocator.destroy(channel);
                slot.* = null;
                channel_count -= 1;
                return;
            }
        }
    }
    return error.ChannelNotFound;
}

/// Get a channel by ID
fn getChannel(id: ChannelId) ChannelError!*Channel {
    for (channels) |slot| {
        if (slot) |channel| {
            if (channel.id == id) return channel;
        }
    }
    return error.ChannelNotFound;
}

/// Send data through a channel
pub fn send(id: ChannelId, data: []const u8, interp_id: i64) ChannelError!void {
    const channel = try getChannel(id);
    return channel.send(data, interp_id);
}

/// Receive data from a channel
pub fn recv(id: ChannelId) ChannelError!ChannelMessage {
    const channel = try getChannel(id);
    return channel.recv();
}

/// Close a channel
pub fn close(id: ChannelId, send_end: bool, recv_end: bool) ChannelError!void {
    _ = send_end;
    _ = recv_end;
    const channel = try getChannel(id);
    channel.close();
}

/// Check if channel is closed
pub fn isClosed(id: ChannelId) ChannelError!bool {
    const channel = try getChannel(id);
    return channel.isClosed();
}

/// Get channel message count
pub fn getCount(id: ChannelId) ChannelError!usize {
    const channel = try getChannel(id);
    return channel.len();
}

/// List all channel IDs
pub fn list_all(alloc: std.mem.Allocator) ChannelError![]ChannelId {
    var ids: std.ArrayList(ChannelId) = .{};
    errdefer ids.deinit(alloc);

    for (channels) |slot| {
        if (slot) |channel| {
            ids.append(alloc, channel.id) catch return error.OutOfMemory;
        }
    }

    return ids.toOwnedSlice(alloc) catch error.OutOfMemory;
}

/// Check if channel exists
pub fn is_valid(id: ChannelId) bool {
    for (channels) |slot| {
        if (slot) |channel| {
            if (channel.id == id) return true;
        }
    }
    return false;
}

/// Release channel associations for an interpreter
pub fn release_all(interp_id: i64) void {
    _ = interp_id;
    // In this simplified implementation, we don't track per-interpreter associations
}

// ============================================================================
// Channel End Operations
// ============================================================================

/// Get a send end for a channel
pub fn get_send_end(id: ChannelId) ChannelError!ChannelId {
    if (!is_valid(id)) return error.ChannelNotFound;
    return id;
}

/// Get a receive end for a channel
pub fn get_recv_end(id: ChannelId) ChannelError!ChannelId {
    if (!is_valid(id)) return error.ChannelNotFound;
    return id;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    channel_count = 0;
    next_channel_id = 1;
    for (&channels) |*slot| {
        slot.* = null;
    }
}

pub fn reset() void {
    // Clean up all channels
    for (&channels) |*slot| {
        if (slot.*) |channel| {
            channel.deinit();
            allocator.destroy(channel);
            slot.* = null;
        }
    }
    channel_count = 0;
    next_channel_id = 1;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "create and destroy channel" {
    reset();

    const id = try create(null);
    try std.testing.expect(id > 0);
    try std.testing.expect(is_valid(id));

    try destroy(id);
    try std.testing.expect(!is_valid(id));
}

test "send and receive" {
    reset();

    const id = try create(null);
    defer destroy(id) catch {};

    try send(id, "hello", 0);
    const msg = try recv(id);
    defer allocator.free(msg.data);

    try std.testing.expectEqualStrings("hello", msg.data);
    try std.testing.expectEqual(@as(i64, 0), msg.interpreter_id);
}

test "receive from empty channel" {
    reset();

    const id = try create(null);
    defer destroy(id) catch {};

    const result = recv(id);
    try std.testing.expectError(error.ChannelEmpty, result);
}

test "send to closed channel" {
    reset();

    const id = try create(null);
    defer destroy(id) catch {};

    try close(id, true, true);

    const result = send(id, "test", 0);
    try std.testing.expectError(error.ChannelClosed, result);
}

test "channel with max size" {
    reset();

    const id = try create(2);
    defer destroy(id) catch {};

    try send(id, "a", 0);
    try send(id, "b", 0);

    const result = send(id, "c", 0);
    try std.testing.expectError(error.SendFailed, result);
}

test "list_all" {
    reset();
    const alloc = std.testing.allocator;

    const id1 = try create(null);
    const id2 = try create(null);
    defer {
        destroy(id1) catch {};
        destroy(id2) catch {};
    }

    const ids = try list_all(alloc);
    defer alloc.free(ids);

    try std.testing.expectEqual(@as(usize, 2), ids.len);
}

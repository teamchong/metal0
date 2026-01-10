//! concurrent.interpreters._crossinterp - Cross-interpreter support
//! Reference: cpython/Lib/concurrent/interpreters/_crossinterp.py
//!
//! Provides utilities for cross-interpreter communication and data sharing.

const std = @import("std");
const interpreters = @import("../interpreters.zig");

// ============================================================================
// Error Types
// ============================================================================

/// Exception raised when data cannot be shared between interpreters
pub const NotShareableError = interpreters.NotShareableError;

// ============================================================================
// ItemInterpreterDestroyed
// ============================================================================

/// CPython: class ItemInterpreterDestroyed(Exception)
/// Exception raised when the owning interpreter has been destroyed
pub const ItemInterpreterDestroyed = error.ItemInterpreterDestroyed;

// ============================================================================
// Shareable Types
// ============================================================================

/// Types that can be shared between interpreters
pub const ShareableType = enum {
    none,
    bool_type,
    int_type,
    float_type,
    bytes_type,
    str_type,
    tuple_type,
    memoryview_type,
};

/// Check if a type is shareable between interpreters
pub fn is_shareable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .void => true,
        .bool => true,
        .int, .comptime_int => true,
        .float, .comptime_float => true,
        .pointer => |p| p.child == u8, // []const u8 (strings/bytes)
        .optional => |o| is_shareable(o.child),
        else => false,
    };
}

// ============================================================================
// CrossInterpreterData
// ============================================================================

/// CPython: struct _xidregistry
/// Registry for cross-interpreter data
pub const CrossInterpreterData = struct {
    const Self = @This();

    /// Data type
    type_name: []const u8,
    /// Serialized data
    data: []const u8,
    /// Source interpreter ID
    source_interp: u64,
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        type_name: []const u8,
        data: []const u8,
        source_interp: u64,
    ) Self {
        return .{
            .allocator = allocator,
            .type_name = type_name,
            .data = data,
            .source_interp = source_interp,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Free any allocated data
    }

    /// Serialize data for cross-interpreter transfer
    pub fn serialize(comptime T: type, value: T, allocator: std.mem.Allocator) ![]u8 {
        if (!is_shareable(T)) {
            return NotShareableError;
        }

        // Simple serialization for basic types
        const info = @typeInfo(T);
        return switch (info) {
            .int, .comptime_int => blk: {
                var buf = try allocator.alloc(u8, @sizeOf(i64));
                const int_val: i64 = @intCast(value);
                std.mem.writeInt(i64, buf[0..8], int_val, .little);
                break :blk buf;
            },
            .float => blk: {
                var buf = try allocator.alloc(u8, @sizeOf(f64));
                const float_bytes: [8]u8 = @bitCast(@as(f64, value));
                @memcpy(buf, &float_bytes);
                break :blk buf;
            },
            .bool => blk: {
                var buf = try allocator.alloc(u8, 1);
                buf[0] = if (value) 1 else 0;
                break :blk buf;
            },
            .pointer => |p| blk: {
                if (p.child == u8) {
                    break :blk try allocator.dupe(u8, value);
                }
                break :blk NotShareableError;
            },
            else => NotShareableError,
        };
    }

    /// Deserialize data from cross-interpreter transfer
    pub fn deserialize(comptime T: type, data: []const u8) !T {
        const info = @typeInfo(T);
        return switch (info) {
            .int => @intCast(std.mem.readInt(i64, data[0..8], .little)),
            .float => @bitCast(data[0..8].*),
            .bool => data[0] != 0,
            .pointer => |p| blk: {
                if (p.child == u8) {
                    break :blk data;
                }
                break :blk NotShareableError;
            },
            else => NotShareableError,
        };
    }
};

// ============================================================================
// ChannelError
// ============================================================================

/// CPython: class ChannelError(Exception)
pub const ChannelError = error.ChannelError;

/// CPython: class ChannelNotFoundError(ChannelError)
pub const ChannelNotFoundError = error.ChannelNotFound;

/// CPython: class ChannelClosedError(ChannelError)
pub const ChannelClosedError = error.ChannelClosed;

/// CPython: class ChannelEmptyError(ChannelError)
pub const ChannelEmptyError = error.ChannelEmpty;

/// CPython: class ChannelNotEmptyError(ChannelError)
pub const ChannelNotEmptyError = error.ChannelNotEmpty;

// ============================================================================
// Channel
// ============================================================================

/// CPython: class SendChannel / RecvChannel
/// A channel for cross-interpreter communication
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        id: u64,
        queue: std.ArrayList(T),
        mutex: std.Thread.Mutex = .{},
        is_closed: bool = false,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, id: u64) Self {
            return .{
                .id = id,
                .queue = std.ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        /// Send an item
        pub fn send(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.is_closed) {
                return ChannelClosedError;
            }

            try self.queue.append(item);
        }

        /// Receive an item
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.queue.items.len == 0) {
                if (self.is_closed) {
                    return ChannelClosedError;
                }
                return ChannelEmptyError;
            }

            return self.queue.orderedRemove(0);
        }

        /// Close the channel
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.is_closed = true;
        }
    };
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get the type name for a value
pub fn getTypeName(comptime T: type) []const u8 {
    return @typeName(T);
}

/// Check if value can be sent across interpreters
pub fn canBeSent(comptime T: type) bool {
    return is_shareable(T);
}

// ============================================================================
// Tests
// ============================================================================

test "is_shareable" {
    try std.testing.expect(is_shareable(i32));
    try std.testing.expect(is_shareable(f64));
    try std.testing.expect(is_shareable(bool));
    try std.testing.expect(is_shareable([]const u8));
    try std.testing.expect(!is_shareable(std.ArrayList(i32)));
}

test "CrossInterpreterData init" {
    const allocator = std.testing.allocator;
    var data = CrossInterpreterData.init(allocator, "int", "42", 0);
    defer data.deinit();

    try std.testing.expectEqualStrings("int", data.type_name);
}

test "Channel basic" {
    const allocator = std.testing.allocator;
    var channel = Channel(i32).init(allocator, 1);
    defer channel.deinit();

    try channel.send(42);
    const val = try channel.recv();
    try std.testing.expectEqual(@as(i32, 42), val);
}

test "Channel close" {
    const allocator = std.testing.allocator;
    var channel = Channel(i32).init(allocator, 1);
    defer channel.deinit();

    channel.close();
    try std.testing.expectError(ChannelClosedError, channel.send(1));
}

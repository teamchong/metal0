//! Event types and SelectorKey for I/O multiplexing.

const std = @import("std");

// ============================================================================
// Event Flags
// ============================================================================

/// Event types for I/O multiplexing
pub const EVENT_READ: u32 = 1 << 0;
pub const EVENT_WRITE: u32 = 1 << 1;

// ============================================================================
// SelectorKey
// ============================================================================

/// Selector key for tracking registered file objects
pub const SelectorKey = struct {
    fileobj: i32, // File descriptor
    fd: i32, // Underlying file descriptor
    events: u32, // Events to monitor (EVENT_READ, EVENT_WRITE)
    data: ?*anyopaque, // User data

    pub fn init(fileobj: i32, events: u32, data: ?*anyopaque) SelectorKey {
        return .{
            .fileobj = fileobj,
            .fd = fileobj,
            .events = events,
            .data = data,
        };
    }
};

// ============================================================================
// Result Type
// ============================================================================

/// Event result from selector
pub const EventResult = struct {
    key: SelectorKey,
    events: u32,
};

// ============================================================================
// Tests
// ============================================================================

test "SelectorKey init" {
    const key = SelectorKey.init(5, EVENT_READ | EVENT_WRITE, null);
    try std.testing.expectEqual(@as(i32, 5), key.fd);
    try std.testing.expectEqual(EVENT_READ | EVENT_WRITE, key.events);
}

test "EVENT flags" {
    try std.testing.expectEqual(@as(u32, 1), EVENT_READ);
    try std.testing.expectEqual(@as(u32, 2), EVENT_WRITE);
}

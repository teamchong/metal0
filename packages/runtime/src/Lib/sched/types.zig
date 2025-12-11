//! Event type and related definitions for the scheduler.

const std = @import("std");

/// A scheduled event
pub const Event = struct {
    const Self = @This();

    /// Time at which to run
    time: i64,
    /// Priority (lower = higher priority)
    priority: i32,
    /// Sequence number for stable sorting
    sequence: usize,
    /// The action to run
    action: Action,
    /// Arguments for the action (opaque)
    argument: ?*anyopaque,
    /// Keyword arguments (opaque)
    kwargs: ?*anyopaque,

    /// Action function type
    pub const Action = *const fn (?*anyopaque, ?*anyopaque) void;

    /// Compare events for priority queue ordering
    pub fn lessThan(_: void, a: Self, b: Self) std.math.Order {
        // First compare by time
        if (a.time < b.time) return .lt;
        if (a.time > b.time) return .gt;

        // Then by priority
        if (a.priority < b.priority) return .lt;
        if (a.priority > b.priority) return .gt;

        // Finally by sequence number (FIFO for equal time/priority)
        if (a.sequence < b.sequence) return .lt;
        if (a.sequence > b.sequence) return .gt;

        return .eq;
    }

    /// Check if this event should run before another
    pub fn isBefore(self: Self, other: Self) bool {
        return lessThan({}, self, other) == .lt;
    }
};

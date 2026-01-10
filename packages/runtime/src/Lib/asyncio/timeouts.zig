//! asyncio.timeouts - Timeout context managers
//! Reference: cpython/Lib/asyncio/timeouts.py
//! Python 3.11+ feature

const std = @import("std");
const futures = @import("futures.zig");
const exceptions = @import("exceptions.zig");

/// Timeout context manager
/// CPython: class Timeout
pub const Timeout = struct {
    when: ?i128, // Deadline in nanoseconds, null = no timeout
    expired: bool,
    reschedule: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, when: ?f64) Timeout {
        const deadline: ?i128 = if (when) |w|
            std.time.nanoTimestamp() + @as(i128, @intFromFloat(w * 1_000_000_000))
        else
            null;

        return .{
            .when = deadline,
            .expired = false,
            .reschedule = false,
            .allocator = allocator,
        };
    }

    /// Enter context (__aenter__)
    pub fn enter(self: *Timeout) !*Timeout {
        return self;
    }

    /// Exit context (__aexit__)
    pub fn exit(self: *Timeout) !void {
        if (self.expired) {
            return exceptions.TimeoutError;
        }
    }

    /// Check if deadline has passed
    pub fn isExpired(self: *Timeout) bool {
        if (self.when) |deadline| {
            if (std.time.nanoTimestamp() >= deadline) {
                self.expired = true;
                return true;
            }
        }
        return false;
    }

    /// Reschedule the timeout deadline
    pub fn rescheduleAt(self: *Timeout, when: ?f64) void {
        if (when) |w| {
            self.when = std.time.nanoTimestamp() + @as(i128, @intFromFloat(w * 1_000_000_000));
        } else {
            self.when = null;
        }
        self.reschedule = true;
        self.expired = false;
    }

    /// Get time remaining until deadline
    pub fn remaining(self: *Timeout) ?f64 {
        if (self.when) |deadline| {
            const now = std.time.nanoTimestamp();
            if (deadline > now) {
                return @as(f64, @floatFromInt(deadline - now)) / 1_000_000_000.0;
            }
            return 0;
        }
        return null;
    }
};

/// Create a timeout context with relative delay
/// CPython: def timeout(delay: float | None) -> Timeout
pub fn timeout(allocator: std.mem.Allocator, delay: ?f64) Timeout {
    return Timeout.init(allocator, delay);
}

/// Create a timeout context with absolute deadline
/// CPython: def timeout_at(when: float | None) -> Timeout
pub fn timeoutAt(allocator: std.mem.Allocator, when: ?f64) Timeout {
    // For timeout_at, 'when' is already an absolute time
    var t = Timeout.init(allocator, null);
    if (when) |w| {
        t.when = @as(i128, @intFromFloat(w * 1_000_000_000));
    }
    return t;
}

// Tests
test "Timeout creation" {
    const allocator = std.testing.allocator;

    var t = timeout(allocator, 1.0); // 1 second timeout
    try std.testing.expect(t.when != null);
    try std.testing.expect(!t.expired);
    try std.testing.expect(!t.isExpired());
}

test "Timeout no deadline" {
    const allocator = std.testing.allocator;

    var t = timeout(allocator, null);
    try std.testing.expect(t.when == null);
    try std.testing.expect(!t.isExpired());
}

test "Timeout remaining" {
    const allocator = std.testing.allocator;

    var t = timeout(allocator, 10.0); // 10 seconds
    const rem = t.remaining();
    try std.testing.expect(rem != null);
    try std.testing.expect(rem.? > 9.0);
}

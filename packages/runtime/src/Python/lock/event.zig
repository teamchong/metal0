/// event - Simple Event Flag
/// Provides signaling between threads

const std = @import("std");
const Atomic = std.atomic.Value;
const helpers = @import("helpers.zig");

// ============================================================================
// Event - Simple Event Flag
// ============================================================================

/// Simple event for signaling between threads
pub const Event = struct {
    set: Atomic(bool) = Atomic(bool).init(false),

    const Self = @This();

    /// Wait for event to be set
    pub fn wait(self: *Self) void {
        while (!self.set.load(.acquire)) {
            helpers.yield();
        }
    }

    /// Wait with timeout (returns true if set, false if timeout)
    pub fn timedWait(self: *Self, timeout_ns: i64) bool {
        if (timeout_ns < 0) {
            self.wait();
            return true;
        }

        const start = std.time.nanoTimestamp();
        while (!self.set.load(.acquire)) {
            const elapsed = std.time.nanoTimestamp() - start;
            if (elapsed >= timeout_ns) {
                return false;
            }
            helpers.yield();
        }
        return true;
    }

    /// Set the event (wake all waiters)
    pub fn set(self: *Self) void {
        self.set.store(true, .release);
    }

    /// Reset the event
    pub fn reset(self: *Self) void {
        self.set.store(false, .release);
    }

    /// Check if set
    pub fn isSet(self: *Self) bool {
        return self.set.load(.acquire);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "event" {
    var event = Event{};

    try std.testing.expect(!event.isSet());

    event.set();
    try std.testing.expect(event.isSet());

    event.reset();
    try std.testing.expect(!event.isSet());
}

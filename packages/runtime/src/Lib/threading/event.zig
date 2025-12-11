//! Event - Thread event object
//!
//! CPython source: Lib/threading.py (Event class)

const std = @import("std");

/// A thread event
pub const Event = struct {
    const Self = @This();

    flag: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .flag = false,
            .mutex = .{},
            .cond = .{},
        };
    }

    /// Return true if the internal flag is true
    pub fn isSet(self: *Self) bool {
        return self.flag;
    }

    /// Set the internal flag to true
    pub fn set(self: *Self) void {
        self.mutex.lock();
        self.flag = true;
        self.cond.broadcast();
        self.mutex.unlock();
    }

    /// Reset the internal flag to false
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        self.flag = false;
        self.mutex.unlock();
    }

    /// Block until the internal flag is true
    pub fn wait(self: *Self, timeout: ?f64) bool {
        _ = timeout;

        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.flag) {
            self.cond.wait(&self.mutex);
        }
        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Event" {
    var event = Event.init();

    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

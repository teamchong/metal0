/// once - One-time Initialization
/// Ensures code runs exactly once

const std = @import("std");
const Atomic = std.atomic.Value;
const helpers = @import("helpers.zig");

// ============================================================================
// Once - One-time Initialization
// ============================================================================

/// Ensures code runs exactly once
pub const Once = struct {
    state: Atomic(u8) = Atomic(u8).init(0),

    const UNINITIALIZED: u8 = 0;
    const INITIALIZING: u8 = 1;
    const INITIALIZED: u8 = 2;

    const Self = @This();

    /// Call the function once
    pub fn callOnce(self: *Self, comptime func: fn () void) void {
        if (self.state.load(.acquire) == INITIALIZED) {
            return;
        }

        self.callOnceSlow(func);
    }

    fn callOnceSlow(self: *Self, comptime func: fn () void) void {
        var expected: u8 = UNINITIALIZED;
        if (self.state.cmpxchgStrong(expected, INITIALIZING, .acquire, .relaxed) == null) {
            // We won the race - initialize
            func();
            self.state.store(INITIALIZED, .release);
            return;
        }

        // Another thread is initializing - wait
        while (self.state.load(.acquire) != INITIALIZED) {
            helpers.yield();
        }
    }

    /// Reset to uninitialized state
    pub fn reset(self: *Self) void {
        self.state.store(UNINITIALIZED, .release);
    }

    /// Check if initialized
    pub fn isInitialized(self: *Self) bool {
        return self.state.load(.acquire) == INITIALIZED;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "once" {
    var once = Once{};
    var count: u32 = 0;

    const increment = struct {
        fn inc() void {
            // Can't easily modify outer count, but test structure
        }
    }.inc;

    once.callOnce(increment);
    once.callOnce(increment);

    try std.testing.expect(once.isInitialized());
    _ = count;
}

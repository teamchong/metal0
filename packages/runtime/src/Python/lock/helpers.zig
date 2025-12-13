/// helpers - Helper functions for lock implementation
/// Provides yield and reinitialization utilities

const std = @import("std");
const builtin = @import("builtin");
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Time after which we hand off lock ownership (1ms in nanoseconds)
pub const TIME_TO_BE_FAIR_NS: i64 = 1_000_000;

/// Maximum spin count before parking (0 if GIL enabled)
pub const MAX_SPIN_COUNT: usize = 40;

/// Lock bits
pub const LOCKED: u8 = 1;
pub const HAS_PARKED: u8 = 2;

// ============================================================================
// Helper Functions
// ============================================================================

/// Yield to other threads
pub fn yield() void {
    if (builtin.os.tag == .windows) {
        // SwitchToThread equivalent
        std.Thread.sleep(0);
    } else {
        // sched_yield equivalent
        std.Thread.sleep(0);
    }
}

/// At fork reinitialization
pub fn atForkReinit(bits: *Atomic(u8)) void {
    bits.store(0, .relaxed);
}

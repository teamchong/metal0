/// lock - Low-level Lock Implementation
/// Mirrors cpython/Python/lock.c
///
/// This module provides low-level lock primitives for the Python runtime:
/// - PyMutex: lightweight mutex with spinning and parking
/// - Once: one-time initialization
/// - Event: simple event flag
/// - RWLock: reader-writer lock
/// - RecursiveMutex: mutex that can be locked multiple times by the same thread
/// - CriticalSection: nested lock management

// Re-export all components
pub const helpers = @import("lock/helpers.zig");
pub const pymutex = @import("lock/pymutex.zig");
pub const once = @import("lock/once.zig");
pub const event = @import("lock/event.zig");
pub const rwlock = @import("lock/rwlock.zig");
pub const recursive_mutex = @import("lock/recursive_mutex.zig");
pub const critical_section = @import("lock/critical_section.zig");

// Re-export primary types and constants
pub const TIME_TO_BE_FAIR_NS = helpers.TIME_TO_BE_FAIR_NS;
pub const MAX_SPIN_COUNT = helpers.MAX_SPIN_COUNT;
pub const LOCKED = helpers.LOCKED;
pub const HAS_PARKED = helpers.HAS_PARKED;

pub const LockStatus = pymutex.LockStatus;
pub const LockFlags = pymutex.LockFlags;
pub const PyMutex = pymutex.PyMutex;
pub const Once = once.Once;
pub const Event = event.Event;
pub const RWLock = rwlock.RWLock;
pub const RecursiveMutex = recursive_mutex.RecursiveMutex;
pub const CriticalSection = critical_section.CriticalSection;

// Re-export helper functions
pub const yield = helpers.yield;
pub const atForkReinit = helpers.atForkReinit;

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "lock module" {
    std.testing.refAllDecls(@This());
}

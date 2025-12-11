/// thread - Thread Support
/// Mirrors cpython/Python/thread.c
///
/// This module provides threading primitives for the Python runtime:
/// - Thread creation and management
/// - Mutex/lock operations
/// - Thread-local storage
/// - Condition variables
/// - Timeout handling

const std = @import("std");
const builtin = @import("builtin");

// Re-export submodules
pub const types = @import("thread/types.zig");
pub const locks = @import("thread/locks.zig");
pub const sync = @import("thread/sync.zig");
pub const tls = @import("thread/tls.zig");
pub const state = @import("thread/state.zig");

// Re-export constants from types.zig
pub const PY_TIMEOUT_MAX = types.PY_TIMEOUT_MAX;
pub const UNSET_TIMEOUT = types.UNSET_TIMEOUT;
pub const DEFAULT_STACKSIZE = types.DEFAULT_STACKSIZE;
pub const LockStatus = types.LockStatus;
pub const LockFlags = types.LockFlags;
pub const parseTimeout = types.parseTimeout;
pub const getStackSize = types.getStackSize;
pub const setStackSize = types.setStackSize;

// Re-export from locks.zig
pub const Lock = locks.Lock;
pub const RLock = locks.RLock;
pub const atForkReinit = locks.atForkReinit;

// Re-export from sync.zig
pub const Condition = sync.Condition;
pub const Semaphore = sync.Semaphore;
pub const Event = sync.Event;
pub const Barrier = sync.Barrier;

// Re-export from tls.zig
pub const TLSKey = tls.TLSKey;

// Re-export from state.zig
pub const Thread = state.Thread;
pub const ThreadState = state.ThreadState;
pub const getCurrentThreadId = state.getCurrentThreadId;
pub const getNumCpus = state.getNumCpus;
pub const getThreadState = state.getThreadState;
pub const setThreadState = state.setThreadState;

// ============================================================================
// Initialization
// ============================================================================

var initialized = false;

/// Initialize thread module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

// ============================================================================
// Tests
// ============================================================================

test {
    _ = types;
    _ = locks;
    _ = sync;
    _ = tls;
    _ = state;
}

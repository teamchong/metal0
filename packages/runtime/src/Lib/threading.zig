//! CPython source: Lib/threading.py
//!
//! Provides higher-level threading interface built on top of std.Thread.
//!
//! Mirrors: CPython Lib/threading.py
//!
//! This is the main entry point that re-exports all threading primitives.

const std = @import("std");

// Re-export all threading primitives
pub const Thread = @import("threading/thread.zig").Thread;
pub const ThreadRegistry = @import("threading/thread.zig").ThreadRegistry;
pub const Lock = @import("threading/lock.zig").Lock;
pub const RLock = @import("threading/rlock.zig").RLock;
pub const Condition = @import("threading/condition.zig").Condition;
pub const Semaphore = @import("threading/semaphore.zig").Semaphore;
pub const BoundedSemaphore = @import("threading/semaphore.zig").BoundedSemaphore;
pub const Event = @import("threading/event.zig").Event;
pub const Barrier = @import("threading/barrier.zig").Barrier;
pub const Timer = @import("threading/timer.zig").Timer;
pub const local = @import("threading/local.zig").local;

// ============================================================================
// Constants
// ============================================================================

/// Default stack size (0 = use system default)
pub const STACK_SIZE = 0;

/// Timeout sentinel value
pub const TIMEOUT_MAX: f64 = std.math.floatMax(f64);

// ============================================================================
// Module Functions
// ============================================================================

/// Return the number of active threads
pub fn activeCount() usize {
    return ThreadRegistry.getCount();
}

/// Register a thread in the global registry (called when thread starts)
pub fn registerThread(thread: *Thread) void {
    ThreadRegistry.register(thread);
}

/// Unregister a thread from the global registry (called when thread ends)
pub fn unregisterThread(thread: *Thread) void {
    ThreadRegistry.unregister(thread);
}

/// Return the current thread
pub fn currentThread(allocator: std.mem.Allocator) !*Thread {
    const t = try allocator.create(Thread);
    t.* = Thread.init(allocator, "MainThread");
    t.started = true;
    t.ident = std.Thread.getCurrentId();
    return t;
}

/// Return the main thread
pub fn mainThread(allocator: std.mem.Allocator) !*Thread {
    return currentThread(allocator);
}

/// Return a list of all active threads
pub fn enumerate(allocator: std.mem.Allocator) ![]const *Thread {
    const registered = try ThreadRegistry.getAll(allocator);
    if (registered.len > 0) {
        return registered;
    }
    // Fallback: at least return main thread
    allocator.free(registered);
    const threads = try allocator.alloc(*Thread, 1);
    threads[0] = try currentThread(allocator);
    return threads;
}

/// Return the thread identifier
pub fn getIdent() std.Thread.Id {
    return std.Thread.getCurrentId();
}

/// Return the native thread identifier
pub fn getNativeId() std.Thread.Id {
    return std.Thread.getCurrentId();
}

/// Set the stack size for new threads
pub fn setStackSize(size: usize) usize {
    _ = size;
    return STACK_SIZE;
}

/// Get the stack size for new threads
pub fn getStackSize() usize {
    return STACK_SIZE;
}

// ============================================================================
// Exception Types
// ============================================================================

pub const ThreadError = error{
    ThreadAlreadyStarted,
    ThreadNotStarted,
    NotOwner,
    BoundedSemaphoreOverflow,
    BrokenBarrier,
};

// ============================================================================
// Tests
// ============================================================================

test "getIdent" {
    const id = getIdent();
    try std.testing.expect(id != 0);
}

test "activeCount" {
    try std.testing.expect(activeCount() >= 1);
}

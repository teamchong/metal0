/// critical_section - Critical Section Implementation
/// Mirrors cpython/Python/critical_section.c
///
/// This module provides critical section primitives for thread safety:
/// - Per-object critical sections
/// - Nested critical sections
/// - Begin/end operations with automatic cleanup
/// - Support for free-threading (PEP 703)

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Maximum nesting depth for critical sections
pub const MAX_NESTING_DEPTH: usize = 8;

/// Critical section state values
pub const State = enum(u8) {
    unlocked = 0,
    locked = 1,
    contended = 2,
};

// ============================================================================
// Critical Section Types
// ============================================================================

/// Critical section for per-object locking
pub const CriticalSection = struct {
    /// Lock state
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    /// Owner thread ID (0 if unlocked)
    owner: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Recursion count
    recursion: u32 = 0,
    /// Previous section in stack (for nesting)
    prev: ?*CriticalSection = null,

    const Self = @This();

    /// Initialize critical section
    pub fn init() Self {
        return .{};
    }

    /// Begin critical section (acquire lock)
    pub fn begin(self: *Self) void {
        const tid = getThreadId();
        const current_owner = self.owner.load(.acquire);

        // Check for recursion
        if (current_owner == tid) {
            self.recursion += 1;
            return;
        }

        // Try to acquire
        while (true) {
            const old = self.state.cmpxchgWeak(
                @intFromEnum(State.unlocked),
                @intFromEnum(State.locked),
                .acquire,
                .monotonic,
            );
            if (old == null) {
                // Successfully acquired
                self.owner.store(tid, .release);
                return;
            }

            // Spin briefly
            std.atomic.spinLoopHint();
        }
    }

    /// Try to begin critical section (non-blocking)
    pub fn tryBegin(self: *Self) bool {
        const tid = getThreadId();
        const current_owner = self.owner.load(.acquire);

        // Check for recursion
        if (current_owner == tid) {
            self.recursion += 1;
            return true;
        }

        // Try to acquire (once)
        const old = self.state.cmpxchgStrong(
            @intFromEnum(State.unlocked),
            @intFromEnum(State.locked),
            .acquire,
            .monotonic,
        );
        if (old == null) {
            self.owner.store(tid, .release);
            return true;
        }

        return false;
    }

    /// End critical section (release lock)
    pub fn end(self: *Self) void {
        // Check recursion
        if (self.recursion > 0) {
            self.recursion -= 1;
            return;
        }

        // Release
        self.owner.store(0, .release);
        self.state.store(@intFromEnum(State.unlocked), .release);
    }

    /// Check if currently held by this thread
    pub fn isHeld(self: *const Self) bool {
        return self.owner.load(.acquire) == getThreadId();
    }

    /// Check if locked (by any thread)
    pub fn isLocked(self: *const Self) bool {
        return self.state.load(.acquire) != @intFromEnum(State.unlocked);
    }
};

// ============================================================================
// Critical Section Stack
// ============================================================================

/// Thread-local stack of critical sections
const CriticalSectionStack = struct {
    sections: [MAX_NESTING_DEPTH]?*CriticalSection = [_]?*CriticalSection{null} ** MAX_NESTING_DEPTH,
    depth: usize = 0,

    const Self = @This();

    /// Push a critical section onto the stack
    pub fn push(self: *Self, cs: *CriticalSection) !void {
        if (self.depth >= MAX_NESTING_DEPTH) {
            return error.MaxNestingExceeded;
        }
        cs.prev = if (self.depth > 0) self.sections[self.depth - 1] else null;
        self.sections[self.depth] = cs;
        self.depth += 1;
    }

    /// Pop the top critical section
    pub fn pop(self: *Self) ?*CriticalSection {
        if (self.depth == 0) return null;
        self.depth -= 1;
        const cs = self.sections[self.depth];
        self.sections[self.depth] = null;
        return cs;
    }

    /// Get current (top) critical section
    pub fn current(self: *const Self) ?*CriticalSection {
        if (self.depth == 0) return null;
        return self.sections[self.depth - 1];
    }

    /// Get nesting depth
    pub fn getDepth(self: *const Self) usize {
        return self.depth;
    }
};

/// Thread-local storage for critical section stack
threadlocal var tls_stack: CriticalSectionStack = .{};

// ============================================================================
// Public API
// ============================================================================

/// Begin a critical section on an object
pub fn Py_BEGIN_CRITICAL_SECTION(cs: *CriticalSection) void {
    cs.begin();
    tls_stack.push(cs) catch {
        // If stack is full, still hold the lock but warn
        @branchHint(.cold);
    };
}

/// End the current critical section
pub fn Py_END_CRITICAL_SECTION() void {
    if (tls_stack.pop()) |cs| {
        cs.end();
    }
}

/// Begin critical section on two objects
pub fn Py_BEGIN_CRITICAL_SECTION2(cs1: *CriticalSection, cs2: *CriticalSection) void {
    // Acquire in consistent order to prevent deadlock
    const order = @intFromPtr(cs1) < @intFromPtr(cs2);
    const first = if (order) cs1 else cs2;
    const second = if (order) cs2 else cs1;

    first.begin();
    tls_stack.push(first) catch {};
    second.begin();
    tls_stack.push(second) catch {};
}

/// End two critical sections
pub fn Py_END_CRITICAL_SECTION2() void {
    // Release in reverse order
    if (tls_stack.pop()) |cs| {
        cs.end();
    }
    if (tls_stack.pop()) |cs| {
        cs.end();
    }
}

/// Get current critical section depth
pub fn getCriticalSectionDepth() usize {
    return tls_stack.getDepth();
}

/// Check if we're in a critical section
pub fn inCriticalSection() bool {
    return tls_stack.depth > 0;
}

/// Release all held critical sections (for cleanup)
pub fn releaseAllCriticalSections() void {
    while (tls_stack.pop()) |cs| {
        cs.end();
    }
}

// ============================================================================
// RAII-style Critical Section Guard
// ============================================================================

/// RAII guard for automatic critical section management
pub const CriticalSectionGuard = struct {
    cs: *CriticalSection,

    const Self = @This();

    pub fn init(cs: *CriticalSection) Self {
        Py_BEGIN_CRITICAL_SECTION(cs);
        return .{ .cs = cs };
    }

    pub fn deinit(self: Self) void {
        _ = self;
        Py_END_CRITICAL_SECTION();
    }
};

/// RAII guard for two critical sections
pub const CriticalSection2Guard = struct {
    cs1: *CriticalSection,
    cs2: *CriticalSection,

    const Self = @This();

    pub fn init(cs1: *CriticalSection, cs2: *CriticalSection) Self {
        Py_BEGIN_CRITICAL_SECTION2(cs1, cs2);
        return .{ .cs1 = cs1, .cs2 = cs2 };
    }

    pub fn deinit(self: Self) void {
        _ = self;
        Py_END_CRITICAL_SECTION2();
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Get current thread ID
fn getThreadId() u64 {
    return @intFromPtr(std.Thread.getCurrentId());
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "critical section basic" {
    var cs = CriticalSection.init();

    try std.testing.expect(!cs.isLocked());

    cs.begin();
    try std.testing.expect(cs.isLocked());
    try std.testing.expect(cs.isHeld());

    cs.end();
    try std.testing.expect(!cs.isLocked());
}

test "critical section recursion" {
    var cs = CriticalSection.init();

    cs.begin();
    try std.testing.expectEqual(@as(u32, 0), cs.recursion);

    cs.begin(); // Recursive
    try std.testing.expectEqual(@as(u32, 1), cs.recursion);

    cs.begin(); // More recursion
    try std.testing.expectEqual(@as(u32, 2), cs.recursion);

    cs.end();
    try std.testing.expectEqual(@as(u32, 1), cs.recursion);

    cs.end();
    try std.testing.expectEqual(@as(u32, 0), cs.recursion);

    cs.end();
    try std.testing.expect(!cs.isLocked());
}

test "critical section try_begin" {
    var cs = CriticalSection.init();

    try std.testing.expect(cs.tryBegin());
    try std.testing.expect(cs.isLocked());

    // Recursive try_begin should succeed
    try std.testing.expect(cs.tryBegin());
    try std.testing.expectEqual(@as(u32, 1), cs.recursion);

    cs.end();
    cs.end();
    try std.testing.expect(!cs.isLocked());
}

test "critical section stack" {
    var stack = CriticalSectionStack{};

    var cs1 = CriticalSection.init();
    var cs2 = CriticalSection.init();

    try stack.push(&cs1);
    try std.testing.expectEqual(@as(usize, 1), stack.getDepth());

    try stack.push(&cs2);
    try std.testing.expectEqual(@as(usize, 2), stack.getDepth());

    const popped1 = stack.pop();
    try std.testing.expect(popped1 == &cs2);
    try std.testing.expectEqual(@as(usize, 1), stack.getDepth());

    const popped2 = stack.pop();
    try std.testing.expect(popped2 == &cs1);
    try std.testing.expectEqual(@as(usize, 0), stack.getDepth());

    const popped3 = stack.pop();
    try std.testing.expect(popped3 == null);
}

test "critical section guard" {
    var cs = CriticalSection.init();

    {
        const guard = CriticalSectionGuard.init(&cs);
        defer guard.deinit();

        try std.testing.expect(cs.isLocked());
    }

    // Guard released
    try std.testing.expect(!cs.isLocked());
}

test "critical section depth" {
    // Reset TLS state
    releaseAllCriticalSections();

    var cs1 = CriticalSection.init();
    var cs2 = CriticalSection.init();

    try std.testing.expectEqual(@as(usize, 0), getCriticalSectionDepth());
    try std.testing.expect(!inCriticalSection());

    Py_BEGIN_CRITICAL_SECTION(&cs1);
    try std.testing.expectEqual(@as(usize, 1), getCriticalSectionDepth());
    try std.testing.expect(inCriticalSection());

    Py_BEGIN_CRITICAL_SECTION(&cs2);
    try std.testing.expectEqual(@as(usize, 2), getCriticalSectionDepth());

    Py_END_CRITICAL_SECTION();
    try std.testing.expectEqual(@as(usize, 1), getCriticalSectionDepth());

    Py_END_CRITICAL_SECTION();
    try std.testing.expectEqual(@as(usize, 0), getCriticalSectionDepth());
    try std.testing.expect(!inCriticalSection());
}

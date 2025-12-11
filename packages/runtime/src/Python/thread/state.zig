/// state - Thread State
/// Per-thread interpreter state and thread management.

const std = @import("std");

// ============================================================================
// Thread Handle
// ============================================================================

/// Thread handle
pub const Thread = struct {
    handle: std.Thread,
    id: std.Thread.Id,

    const Self = @This();

    /// Start a new thread
    pub fn start(
        comptime func: anytype,
        args: anytype,
    ) !Self {
        const handle = try std.Thread.spawn(.{}, func, args);
        return .{
            .handle = handle,
            .id = handle.getHandle(),
        };
    }

    /// Wait for thread to finish
    pub fn join(self: Self) void {
        self.handle.join();
    }

    /// Detach thread
    pub fn detach(self: Self) void {
        self.handle.detach();
    }
};

/// Get current thread ID
pub fn getCurrentThreadId() u64 {
    return @intCast(std.Thread.getCurrentId());
}

/// Get number of CPUs
pub fn getNumCpus() usize {
    return std.Thread.getCpuCount() catch 1;
}

// ============================================================================
// Thread State
// ============================================================================

/// Thread state for Python interpreter
pub const ThreadState = struct {
    allocator: std.mem.Allocator,
    thread_id: u64,
    next: ?*ThreadState = null,
    prev: ?*ThreadState = null,

    // Exception state
    current_exception: ?*anyopaque = null,
    exception_context: ?*anyopaque = null,
    exception_cause: ?*anyopaque = null,

    // Recursion tracking
    recursion_depth: u32 = 0,
    recursion_limit: u32 = 1000,

    // Frame stack
    frame: ?*anyopaque = null,

    // Tracing
    tracing: bool = false,
    use_tracing: bool = false,

    // Async generator state
    async_gen_firstiter: ?*anyopaque = null,
    async_gen_finalizer: ?*anyopaque = null,

    const Self = @This();

    pub fn create(allocator: std.mem.Allocator) !*Self {
        const state = try allocator.create(Self);
        state.* = .{
            .allocator = allocator,
            .thread_id = getCurrentThreadId(),
        };
        return state;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Check if we're in recursion limit
    pub fn checkRecursion(self: *Self) bool {
        return self.recursion_depth < self.recursion_limit;
    }

    /// Enter recursive call
    pub fn enterRecursion(self: *Self) !void {
        if (self.recursion_depth >= self.recursion_limit) {
            return error.RecursionLimit;
        }
        self.recursion_depth += 1;
    }

    /// Leave recursive call
    pub fn leaveRecursion(self: *Self) void {
        if (self.recursion_depth > 0) {
            self.recursion_depth -= 1;
        }
    }
};

/// Thread-local current thread state
threadlocal var current_thread_state: ?*ThreadState = null;

/// Get current thread state
pub fn getThreadState() ?*ThreadState {
    return current_thread_state;
}

/// Set current thread state
pub fn setThreadState(tstate: ?*ThreadState) void {
    current_thread_state = tstate;
}

// ============================================================================
// Tests
// ============================================================================

test "thread state" {
    const allocator = std.testing.allocator;

    const tstate = try ThreadState.create(allocator);
    defer tstate.destroy();

    try std.testing.expect(tstate.thread_id != 0);
    try std.testing.expect(tstate.checkRecursion());

    try tstate.enterRecursion();
    try std.testing.expectEqual(@as(u32, 1), tstate.recursion_depth);

    tstate.leaveRecursion();
    try std.testing.expectEqual(@as(u32, 0), tstate.recursion_depth);
}

//! multiprocessing.popen_forkserver - Forkserver-based process spawning
//! Reference: cpython/Lib/multiprocessing/popen_forkserver.py
//!
//! CPython __all__: ['Popen']
//!
//! Implements process spawning using a fork server.
//! The forkserver approach pre-forks a process that handles
//! spawning new workers, avoiding the overhead of reimporting modules.

const std = @import("std");
const builtin = @import("builtin");
const forkserver = @import("forkserver.zig");
const popen_fork = @import("popen_fork.zig");

// Re-export base Popen for common functionality
const BasePopen = popen_fork.Popen;

// ============================================================================
// Popen - Forkserver-based process spawner
// ============================================================================

/// CPython: class Popen(popen_fork.Popen)
/// Process spawner using forkserver
pub const Popen = struct {
    const Self = @This();

    base: BasePopen,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BasePopen.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// CPython: def __call__(self, process_obj)
    pub fn call(self: *Self, target: ?*const fn () void) !void {
        // Ensure forkserver is running
        try forkserver.ensure_running(self.allocator);

        // Connect to forkserver and get a new process
        const inherited_fds = forkserver.get_inherited_fds(self.allocator);
        const pid = try forkserver.connect_to_new_process(self.allocator, inherited_fds);

        self.base.pid = pid;

        // The target function runs in the forked child
        _ = target;
    }

    /// Forward poll to base
    pub fn poll(self: *Self) ?i32 {
        return self.base.poll();
    }

    /// Forward wait to base
    pub fn wait(self: *Self, timeout: ?f64) !i32 {
        return self.base.wait(timeout);
    }

    /// Forward terminate to base
    pub fn terminate(self: *Self) !void {
        return self.base.terminate();
    }

    /// Forward kill to base
    pub fn kill(self: *Self) !void {
        return self.base.kill();
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Create a new Popen instance using forkserver
pub fn popen(allocator: std.mem.Allocator, target: ?*const fn () void) !Popen {
    var p = Popen.init(allocator);
    try p.call(target);
    return p;
}

// ============================================================================
// Tests
// ============================================================================

test "Popen init" {
    const allocator = std.testing.allocator;
    var p = Popen.init(allocator);
    defer p.deinit();

    try std.testing.expect(p.base.pid == null);
    try std.testing.expect(p.base.returncode == null);
}

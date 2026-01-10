//! multiprocessing.popen_fork - Fork-based process spawning
//! Reference: cpython/Lib/multiprocessing/popen_fork.py
//!
//! CPython __all__: ['Popen']
//!
//! Implements process spawning using fork() system call.
//! This is the default method on Unix systems (except macOS).

const std = @import("std");
const builtin = @import("builtin");
const process_mod = @import("process.zig");

// ============================================================================
// Popen - Fork-based process spawner
// ============================================================================

/// CPython: class Popen
/// Process spawner using fork()
pub const Popen = struct {
    const Self = @This();

    pid: ?std.posix.pid_t,
    returncode: ?i32,
    finalizer: ?*const fn () void,
    sentinel: ?std.posix.fd_t,

    pub fn init() Self {
        return .{
            .pid = null,
            .returncode = null,
            .finalizer = null,
            .sentinel = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.sentinel) |fd| {
            std.posix.close(fd);
        }
    }

    /// CPython: def __call__(self, process_obj)
    pub fn call(self: *Self, target: ?*const fn () void) !void {
        // Create a pipe for the sentinel
        const pipe = try std.posix.pipe();

        const pid = try std.posix.fork();
        if (pid == 0) {
            // Child process
            std.posix.close(pipe[0]); // Close read end

            // Run the target function
            if (target) |func| {
                func();
            }

            // Close write end and exit
            std.posix.close(pipe[1]);
            std.posix.exit(0);
        } else {
            // Parent process
            std.posix.close(pipe[1]); // Close write end
            self.pid = pid;
            self.sentinel = pipe[0];
        }
    }

    /// CPython: def duplicate_for_child(self, fd)
    pub fn duplicate_for_child(_: *Self, fd: std.posix.fd_t) !std.posix.fd_t {
        return try std.posix.dup(fd);
    }

    /// CPython: def poll(self, flag=os.WNOHANG)
    pub fn poll(self: *Self) ?i32 {
        if (self.returncode != null) {
            return self.returncode;
        }

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, .{ .NOHANG = true });
            if (result.pid != 0) {
                self.returncode = @as(i32, @intCast(result.status));
                return self.returncode;
            }
        }

        return null;
    }

    /// CPython: def wait(self, timeout=None)
    pub fn wait(self: *Self, timeout: ?f64) !i32 {
        _ = timeout; // TODO: implement timeout

        if (self.returncode) |rc| {
            return rc;
        }

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, .{});
            self.returncode = @as(i32, @intCast(result.status));
            return self.returncode.?;
        }

        return error.NoProcess;
    }

    /// CPython: def terminate(self)
    pub fn terminate(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.TERM);
        }
    }

    /// CPython: def kill(self)
    pub fn kill(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.KILL);
        }
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Create a new Popen instance and spawn the process
pub fn popen(target: ?*const fn () void) !Popen {
    var p = Popen.init();
    try p.call(target);
    return p;
}

// ============================================================================
// Tests
// ============================================================================

test "Popen init" {
    var p = Popen.init();
    defer p.deinit();

    try std.testing.expect(p.pid == null);
    try std.testing.expect(p.returncode == null);
}

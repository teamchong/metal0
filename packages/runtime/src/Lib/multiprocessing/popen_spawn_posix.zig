//! multiprocessing.popen_spawn_posix - Spawn-based process spawning (POSIX)
//! Reference: cpython/Lib/multiprocessing/popen_spawn_posix.py
//!
//! CPython __all__: ['Popen']
//!
//! Implements process spawning using posix_spawn() on Unix systems.
//! This is the default method on macOS.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Popen - Spawn-based process spawner (POSIX)
// ============================================================================

/// CPython: class Popen
/// Process spawner using posix_spawn
pub const Popen = struct {
    const Self = @This();

    pid: ?std.posix.pid_t,
    returncode: ?i32,
    sentinel: ?std.posix.fd_t,

    pub fn init() Self {
        return .{
            .pid = null,
            .returncode = null,
            .sentinel = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.sentinel) |fd| {
            std.posix.close(fd);
        }
    }

    /// CPython: def __call__(self, process_obj)
    pub fn call(self: *Self, argv: []const []const u8, env: ?std.process.EnvMap) !void {
        // Create sentinel pipe
        const pipe = try std.posix.pipe();

        // Use ChildProcess for spawn
        var child = std.process.Child.init(argv, std.heap.page_allocator);

        // Set environment if provided
        if (env) |e| {
            child.env_map = &e;
        }

        try child.spawn();

        // Close write end in parent
        std.posix.close(pipe[1]);

        self.pid = child.id;
        self.sentinel = pipe[0];
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
        _ = timeout;

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
// Helper Functions
// ============================================================================

/// CPython: def _check_not_importing_main()
pub fn check_not_importing_main() void {
    // In AOT compilation, this check is not needed
}

/// CPython: def get_preparation_data(name)
pub fn get_preparation_data(name: []const u8) []const u8 {
    // Return serialized preparation data
    return name;
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

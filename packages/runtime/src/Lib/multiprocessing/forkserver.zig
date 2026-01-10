//! multiprocessing.forkserver - Fork server for process spawning
//! Reference: cpython/Lib/multiprocessing/forkserver.py
//!
//! CPython __all__: ['ensure_running', 'get_inherited_fds', 'connect_to_new_process',
//!                   'set_forkserver_preload', 'get_forkserver_preload']
//!
//! The forkserver approach spawns a server process at the start,
//! which then forks new worker processes on request. This avoids
//! the overhead of importing modules in each child.

const std = @import("std");
const builtin = @import("builtin");
const connection = @import("connection.zig");

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of inherited file descriptors
pub const MAXFDS_TO_SEND: usize = 256;

/// Forkserver exit codes
pub const EXIT_FORKSERVER: u8 = 1;

// ============================================================================
// ForkServer State
// ============================================================================

/// Global forkserver state
var _forkserver: ?ForkServer = null;
var _forkserver_lock: std.Thread.Mutex = .{};

/// CPython: class ForkServer
pub const ForkServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _forkserver_alive_fd: ?std.posix.fd_t,
    _forkserver_address: ?[]const u8,
    _preload_modules: std.ArrayList([]const u8),
    _inherited_fds: std.ArrayList(std.posix.fd_t),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._forkserver_alive_fd = null,
            ._forkserver_address = null,
            ._preload_modules = .{},
            ._inherited_fds = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._forkserver_alive_fd) |fd| {
            std.posix.close(fd);
        }
        self._preload_modules.deinit(self.allocator);
        self._inherited_fds.deinit(self.allocator);
    }

    /// CPython: def set_forkserver_preload(self, modules_names)
    pub fn set_forkserver_preload(self: *Self, modules: []const []const u8) !void {
        self._preload_modules.clearRetainingCapacity();
        for (modules) |m| {
            try self._preload_modules.append(self.allocator, m);
        }
    }

    /// CPython: def get_forkserver_preload(self)
    pub fn get_forkserver_preload(self: *Self) []const []const u8 {
        return self._preload_modules.items;
    }

    /// CPython: def get_inherited_fds(self)
    pub fn get_inherited_fds(self: *Self) []const std.posix.fd_t {
        return self._inherited_fds.items;
    }

    /// CPython: def set_inherited_fds(self, fds)
    pub fn set_inherited_fds(self: *Self, fds: []const std.posix.fd_t) !void {
        self._inherited_fds.clearRetainingCapacity();
        for (fds) |fd| {
            try self._inherited_fds.append(self.allocator, fd);
        }
    }

    /// CPython: def ensure_running(self)
    pub fn ensure_running(self: *Self) !void {
        if (self._forkserver_alive_fd != null) {
            return; // Already running
        }

        // On non-Unix platforms, forkserver is not supported
        if (builtin.os.tag == .windows) {
            return error.ForkserverNotSupported;
        }

        // Create a socket pair for communication
        const pipe = try std.posix.pipe();

        const pid = try std.posix.fork();
        if (pid == 0) {
            // Child - become the forkserver
            std.posix.close(pipe[0]);
            self.runForkserver(pipe[1]);
            std.posix.exit(0);
        } else {
            // Parent
            std.posix.close(pipe[1]);
            self._forkserver_alive_fd = pipe[0];
        }
    }

    /// Internal: Run the forkserver loop
    fn runForkserver(self: *Self, comm_fd: std.posix.fd_t) void {
        _ = self;
        // Simple forkserver loop - wait for commands and fork
        var buf: [1024]u8 = undefined;
        while (true) {
            const n = std.posix.read(comm_fd, &buf) catch break;
            if (n == 0) break; // EOF - parent closed connection

            // Fork a new process
            const child_pid = std.posix.fork() catch continue;
            if (child_pid == 0) {
                // Child process - exit forkserver loop
                return;
            }
            // Parent (forkserver) continues waiting
        }
    }

    /// CPython: def connect_to_new_process(self, fds)
    pub fn connect_to_new_process(self: *Self, fds: []const std.posix.fd_t) !std.posix.pid_t {
        try self.ensure_running();
        _ = fds;

        // Send fork request to forkserver
        if (self._forkserver_alive_fd) |fd| {
            const msg = "fork";
            _ = try std.posix.write(fd, msg);

            // Wait for response with child PID
            // In practice, this would use SCM_RIGHTS to pass fds
            var buf: [32]u8 = undefined;
            const n = try std.posix.read(fd, &buf);
            if (n > 0) {
                // Parse PID from response
                const pid_str = buf[0..n];
                return std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, pid_str, &[_]u8{ '\n', '\r', ' ' }), 10) catch return error.InvalidResponse;
            }
        }

        return error.ForkserverNotRunning;
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Get or create the global forkserver
pub fn get_forkserver(allocator: std.mem.Allocator) *ForkServer {
    _forkserver_lock.lock();
    defer _forkserver_lock.unlock();

    if (_forkserver == null) {
        _forkserver = ForkServer.init(allocator);
    }
    return &_forkserver.?;
}

/// CPython: def ensure_running()
pub fn ensure_running(allocator: std.mem.Allocator) !void {
    const fs = get_forkserver(allocator);
    try fs.ensure_running();
}

/// CPython: def get_inherited_fds()
pub fn get_inherited_fds(allocator: std.mem.Allocator) []const std.posix.fd_t {
    const fs = get_forkserver(allocator);
    return fs.get_inherited_fds();
}

/// CPython: def connect_to_new_process(fds)
pub fn connect_to_new_process(allocator: std.mem.Allocator, fds: []const std.posix.fd_t) !std.posix.pid_t {
    const fs = get_forkserver(allocator);
    return fs.connect_to_new_process(fds);
}

/// CPython: def set_forkserver_preload(modules_names)
pub fn set_forkserver_preload(allocator: std.mem.Allocator, modules: []const []const u8) !void {
    const fs = get_forkserver(allocator);
    try fs.set_forkserver_preload(modules);
}

/// CPython: def get_forkserver_preload()
pub fn get_forkserver_preload(allocator: std.mem.Allocator) []const []const u8 {
    const fs = get_forkserver(allocator);
    return fs.get_forkserver_preload();
}

// ============================================================================
// Tests
// ============================================================================

test "ForkServer init" {
    const allocator = std.testing.allocator;
    var fs = ForkServer.init(allocator);
    defer fs.deinit();

    try std.testing.expect(fs._forkserver_alive_fd == null);
    try std.testing.expect(fs._preload_modules.items.len == 0);
}

test "set_forkserver_preload" {
    const allocator = std.testing.allocator;
    var fs = ForkServer.init(allocator);
    defer fs.deinit();

    try fs.set_forkserver_preload(&[_][]const u8{ "os", "sys" });
    try std.testing.expectEqual(@as(usize, 2), fs._preload_modules.items.len);
}

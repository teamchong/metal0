//! Process class for multiprocessing module
const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// A process object representing an activity run in a separate process
pub const Process = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    pid: ?std.posix.pid_t,
    daemon: bool,
    exitcode: ?i32,
    target: ?*const fn () void,
    args: ?[]const []const u8,
    kwargs: ?hashmap_helper.StringHashMap([]const u8),
    started: bool,
    sentinel: ?i32,

    pub fn init(
        allocator: std.mem.Allocator,
        target: ?*const fn () void,
        name: ?[]const u8,
        args: ?[]const []const u8,
        daemon: bool,
    ) Self {
        return .{
            .allocator = allocator,
            .name = name orelse "Process",
            .pid = null,
            .daemon = daemon,
            .exitcode = null,
            .target = target,
            .args = args,
            .kwargs = null,
            .started = false,
            .sentinel = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.kwargs) |*kw| {
            kw.deinit();
        }
    }

    /// Start the process
    pub fn start(self: *Self) !void {
        if (self.started) {
            return error.ProcessAlreadyStarted;
        }

        const pid = try std.posix.fork();
        if (pid == 0) {
            // Child process
            if (self.target) |target_fn| {
                target_fn();
            }
            std.posix.exit(0);
        } else {
            // Parent process
            self.pid = pid;
            self.started = true;
        }
    }

    /// Wait for process to terminate
    pub fn join(self: *Self, timeout: ?f64) !void {
        _ = timeout;
        if (!self.started) {
            return error.ProcessNotStarted;
        }

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, 0);
            self.exitcode = @as(i32, @intCast(result.status));
            self.pid = null;
        }
    }

    /// Check if process is alive
    pub fn isAlive(self: *Self) bool {
        if (!self.started) return false;
        if (self.exitcode != null) return false;

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, std.posix.W.NOHANG);
            if (result.pid != 0) {
                self.exitcode = @as(i32, @intCast(result.status));
                return false;
            }
            return true;
        }
        return false;
    }

    /// Terminate the process
    pub fn terminate(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.TERM);
        }
    }

    /// Kill the process (forcefully)
    pub fn kill(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.KILL);
        }
    }

    /// Get process ID
    pub fn getPid(self: *Self) ?std.posix.pid_t {
        return self.pid;
    }

    /// Get exit code
    pub fn getExitcode(self: *Self) ?i32 {
        return self.exitcode;
    }
};

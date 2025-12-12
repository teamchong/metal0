//! CPython source: Lib/subprocess.py
//!
//! Provides functions for spawning and managing child processes.
//! Supports pipes, environment variables, and shell commands.
//!
//! Mirrors: CPython Lib/subprocess.py

const std = @import("std");
const builtin = @import("builtin");

/// Standard file descriptors for subprocess I/O
pub const PIPE = -1;
pub const STDOUT = -2;
pub const DEVNULL = -3;

/// Result from run() function
pub const CompletedProcess = struct {
    args: []const []const u8,
    returncode: i32,
    stdout: ?[]u8,
    stderr: ?[]u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CompletedProcess) void {
        if (self.stdout) |s| self.allocator.free(s);
        if (self.stderr) |s| self.allocator.free(s);
    }
};

/// Process object for more control over subprocess
pub const Popen = struct {
    child: std.process.Child,
    args: []const []const u8,
    allocator: std.mem.Allocator,
    returncode: ?i32,

    pub fn init(allocator: std.mem.Allocator, args: []const []const u8, options: struct {
        stdin: ?std.process.Child.StdIo = null,
        stdout: ?std.process.Child.StdIo = null,
        stderr: ?std.process.Child.StdIo = null,
        cwd: ?[]const u8 = null,
        env: ?*const std.process.EnvMap = null,
    }) !Popen {
        var child = std.process.Child.init(args, allocator);

        if (options.stdin) |s| child.stdin_behavior = s;
        if (options.stdout) |s| child.stdout_behavior = s;
        if (options.stderr) |s| child.stderr_behavior = s;
        if (options.cwd) |c| child.cwd = c;
        if (options.env) |e| child.env_map = e;

        try child.spawn();

        return .{
            .child = child,
            .args = args,
            .allocator = allocator,
            .returncode = null,
        };
    }

    /// Wait for process to terminate
    pub fn wait(self: *Popen) !i32 {
        const term = try self.child.wait();
        self.returncode = switch (term) {
            .Exited => |code| @as(i32, code),
            .Signal => |sig| -@as(i32, @intCast(sig)),
            .Stopped => |sig| -@as(i32, @intCast(sig)),
            .Unknown => |val| @as(i32, @intCast(val)),
        };
        return self.returncode.?;
    }

    /// Check if process has terminated (non-blocking)
    pub fn poll(self: *Popen) ?i32 {
        // If already have return code, return it
        if (self.returncode) |code| {
            return code;
        }

        // Try non-blocking wait using WNOHANG
        const result = std.posix.waitpid(self.child.id, .{ .NOHANG = true });
        if (result.pid == 0) {
            // Process still running
            return null;
        }

        // Process terminated - compute return code
        const term = result.status;
        self.returncode = switch (term) {
            .exited => |code| @as(i32, code),
            .signal => |sig| -@as(i32, @intCast(@intFromEnum(sig))),
            .stopped => |sig| -@as(i32, @intCast(@intFromEnum(sig))),
            .unknown => |val| @as(i32, @intCast(val)),
        };
        return self.returncode;
    }

    /// Read stdout and stderr, wait for termination
    pub fn communicate(self: *Popen) !struct { stdout: ?[]u8, stderr: ?[]u8, returncode: i32 } {
        var stdout_data: ?[]u8 = null;
        var stderr_data: ?[]u8 = null;

        if (self.child.stdout) |stdout| {
            stdout_data = try stdout.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        }

        if (self.child.stderr) |stderr| {
            stderr_data = try stderr.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        }

        const code = try self.wait();

        return .{
            .stdout = stdout_data,
            .stderr = stderr_data,
            .returncode = code,
        };
    }

    /// Terminate the process (SIGTERM)
    pub fn terminate(self: *Popen) !void {
        try std.posix.kill(self.child.id, std.posix.SIG.TERM);
    }

    /// Kill the process (SIGKILL)
    pub fn kill(self: *Popen) !void {
        try std.posix.kill(self.child.id, std.posix.SIG.KILL);
    }

    pub fn deinit(self: *Popen) void {
        self.child.deinit();
    }
};

/// Run a command and wait for completion
pub fn run(allocator: std.mem.Allocator, args: []const []const u8, options: struct {
    capture_output: bool = false,
    check: bool = false,
    cwd: ?[]const u8 = null,
    env: ?*const std.process.EnvMap = null,
    timeout: ?u64 = null,
}) !CompletedProcess {
    var child = std.process.Child.init(args, allocator);

    if (options.capture_output) {
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
    }

    if (options.cwd) |c| child.cwd = c;
    if (options.env) |e| child.env_map = e;

    try child.spawn();

    var stdout_data: ?[]u8 = null;
    var stderr_data: ?[]u8 = null;

    // Handle timeout if specified
    if (options.timeout) |timeout_ns| {
        const start_time = std.time.nanoTimestamp();
        const deadline = start_time + @as(i128, timeout_ns);

        // Poll for completion with timeout
        while (true) {
            const result = std.posix.waitpid(child.id, .{ .NOHANG = true });
            if (result.pid != 0) {
                // Process completed
                break;
            }

            // Check timeout
            if (std.time.nanoTimestamp() >= deadline) {
                // Timeout - kill the process
                std.posix.kill(child.id, std.posix.SIG.KILL) catch {};
                _ = std.posix.waitpid(child.id, .{});
                return error.TimeoutExpired;
            }

            // Sleep briefly before polling again
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }

    if (options.capture_output) {
        if (child.stdout) |stdout| {
            stdout_data = try stdout.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        }
        if (child.stderr) |stderr| {
            stderr_data = try stderr.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        }
    }

    const term = try child.wait();
    const returncode: i32 = switch (term) {
        .Exited => |code| @as(i32, code),
        .Signal => |sig| -@as(i32, @intCast(sig)),
        .Stopped => |sig| -@as(i32, @intCast(sig)),
        .Unknown => |val| @as(i32, @intCast(val)),
    };

    if (options.check and returncode != 0) {
        if (stdout_data) |s| allocator.free(s);
        if (stderr_data) |s| allocator.free(s);
        return error.CalledProcessError;
    }

    return .{
        .args = args,
        .returncode = returncode,
        .stdout = stdout_data,
        .stderr = stderr_data,
        .allocator = allocator,
    };
}

/// Run command and return exit code only
pub fn call(allocator: std.mem.Allocator, args: []const []const u8) !i32 {
    var result = try run(allocator, args, .{});
    defer result.deinit();
    return result.returncode;
}

/// Run command, check return code
pub fn check_call(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var result = try run(allocator, args, .{ .check = true });
    defer result.deinit();
}

/// Run command and return output
pub fn check_output(allocator: std.mem.Allocator, args: []const []const u8) ![]u8 {
    const result = try run(allocator, args, .{ .capture_output = true, .check = true });
    defer {
        if (result.stderr) |s| allocator.free(s);
    }
    return result.stdout orelse return error.NoOutput;
}

/// Get output of shell command
pub fn getoutput(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    const shell = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/c", cmd }
    else
        &[_][]const u8{ "/bin/sh", "-c", cmd };

    return check_output(allocator, shell);
}

/// Get status and output of shell command
pub fn getstatusoutput(allocator: std.mem.Allocator, cmd: []const u8) !struct { status: i32, output: []u8 } {
    const shell = if (builtin.os.tag == .windows)
        &[_][]const u8{ "cmd.exe", "/c", cmd }
    else
        &[_][]const u8{ "/bin/sh", "-c", cmd };

    const result = try run(allocator, shell, .{ .capture_output = true });
    defer {
        if (result.stderr) |s| allocator.free(s);
    }

    return .{
        .status = result.returncode,
        .output = result.stdout orelse try allocator.dupe(u8, ""),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "run simple command" {
    const allocator = std.testing.allocator;

    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var result = try run(allocator, &[_][]const u8{ "echo", "hello" }, .{ .capture_output = true });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 0), result.returncode);
    if (result.stdout) |stdout| {
        try std.testing.expectEqualStrings("hello\n", stdout);
    }
}

test "call" {
    const allocator = std.testing.allocator;

    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const code = try call(allocator, &[_][]const u8{ "true" });
    try std.testing.expectEqual(@as(i32, 0), code);

    const code2 = try call(allocator, &[_][]const u8{ "false" });
    try std.testing.expectEqual(@as(i32, 1), code2);
}

test "check_output" {
    const allocator = std.testing.allocator;

    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const output = try check_output(allocator, &[_][]const u8{ "echo", "test" });
    defer allocator.free(output);

    try std.testing.expectEqualStrings("test\n", output);
}

test "getstatusoutput" {
    const allocator = std.testing.allocator;

    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const result = try getstatusoutput(allocator, "echo hello");
    defer allocator.free(result.output);

    try std.testing.expectEqual(@as(i32, 0), result.status);
    try std.testing.expectEqualStrings("hello\n", result.output);
}

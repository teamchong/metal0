//! asyncio.subprocess - Subprocess support for asyncio
//! Reference: cpython/Lib/asyncio/subprocess.py
//! Wraps runtime subprocess module

const std = @import("std");
const futures = @import("futures.zig");
const transports = @import("transports.zig");
const protocols = @import("protocols.zig");
const streams = @import("streams.zig");

/// Subprocess pipe constants
pub const PIPE: i32 = -1;
pub const STDOUT: i32 = -2;
pub const DEVNULL: i32 = -3;

/// Process class for managing subprocesses
/// CPython: class Process
pub const Process = struct {
    transport: ?*transports.SubprocessTransport,
    stdin: ?*streams.StreamWriter,
    stdout: ?*streams.StreamReader,
    stderr: ?*streams.StreamReader,
    pid: ?i32,
    returncode: ?i32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Process {
        return .{
            .transport = null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .pid = null,
            .returncode = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Process) void {
        if (self.stdin) |s| {
            self.allocator.destroy(s);
        }
        if (self.stdout) |s| {
            s.deinit();
            self.allocator.destroy(s);
        }
        if (self.stderr) |s| {
            s.deinit();
            self.allocator.destroy(s);
        }
        if (self.transport) |t| {
            t.deinit();
            self.allocator.destroy(t);
        }
    }

    /// Wait for child process to terminate
    pub fn wait(self: *Process) !i32 {
        while (self.returncode == null) {
            std.Thread.sleep(10_000); // 10µs
        }
        return self.returncode.?;
    }

    /// Communicate with process: send input and read output
    pub fn communicate(self: *Process, input: ?[]const u8) !struct { stdout: ?[]u8, stderr: ?[]u8 } {
        // Write input if provided
        if (input) |data| {
            if (self.stdin) |stdin| {
                try stdin.write(data);
                stdin.close();
            }
        }

        // Read stdout
        var stdout_data: ?[]u8 = null;
        if (self.stdout) |stdout| {
            stdout_data = try stdout.read(-1);
        }

        // Read stderr
        var stderr_data: ?[]u8 = null;
        if (self.stderr) |stderr| {
            stderr_data = try stderr.read(-1);
        }

        // Wait for completion
        _ = try self.wait();

        return .{ .stdout = stdout_data, .stderr = stderr_data };
    }

    /// Send signal to process
    pub fn sendSignal(self: *Process, signal: i32) void {
        if (self.transport) |t| {
            t.sendSignal(signal);
        }
    }

    /// Terminate the process with SIGTERM
    pub fn terminate(self: *Process) void {
        self.sendSignal(15);
    }

    /// Kill the process with SIGKILL
    pub fn kill(self: *Process) void {
        self.sendSignal(9);
    }
};

/// Create subprocess using exec
/// CPython: async def create_subprocess_exec(*args, ...)
pub fn createSubprocessExec(
    allocator: std.mem.Allocator,
    program: []const u8,
    args: []const []const u8,
    options: CreateSubprocessOptions,
) !*Process {
    _ = program;
    _ = args;
    _ = options;

    const process = try allocator.create(Process);
    process.* = Process.init(allocator);

    // In real implementation, would spawn child process here
    // using std.ChildProcess

    return process;
}

/// Create subprocess using shell
/// CPython: async def create_subprocess_shell(cmd, ...)
pub fn createSubprocessShell(
    allocator: std.mem.Allocator,
    cmd: []const u8,
    options: CreateSubprocessOptions,
) !*Process {
    // Shell execution - wrap command in shell
    const shell_args = [_][]const u8{ "/bin/sh", "-c", cmd };
    return createSubprocessExec(allocator, "/bin/sh", &shell_args, options);
}

/// Options for creating subprocess
pub const CreateSubprocessOptions = struct {
    stdin: i32 = 0, // 0 = inherit, PIPE = pipe, DEVNULL = /dev/null
    stdout: i32 = 0,
    stderr: i32 = 0,
    cwd: ?[]const u8 = null,
    env: ?std.StringHashMap([]const u8) = null,
    limit: usize = streams._DEFAULT_LIMIT,
};

// Tests
test "Process creation" {
    const allocator = std.testing.allocator;

    var process = Process.init(allocator);
    defer process.deinit();

    try std.testing.expect(process.pid == null);
    try std.testing.expect(process.returncode == null);
}

test "Pipe constants" {
    try std.testing.expectEqual(@as(i32, -1), PIPE);
    try std.testing.expectEqual(@as(i32, -2), STDOUT);
    try std.testing.expectEqual(@as(i32, -3), DEVNULL);
}

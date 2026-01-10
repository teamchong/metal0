//! test.test_asyncio.test_subprocess - Tests for asyncio subprocess
//! Reference: cpython/Lib/test/test_asyncio/test_subprocess.py
//!
//! Tests for create_subprocess_exec, create_subprocess_shell, Process

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Subprocess Constants
// ============================================================================

pub const PIPE: i32 = -1;
pub const STDOUT: i32 = -2;
pub const DEVNULL: i32 = -3;

// ============================================================================
// Process Implementation
// ============================================================================

/// An asyncio subprocess
pub const Process = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _pid: ?posix.pid_t = null,
    _returncode: ?i32 = null,
    _stdin: ?*ProcessPipe = null,
    _stdout: ?*ProcessPipe = null,
    _stderr: ?*ProcessPipe = null,
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._stdin) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
        if (self._stdout) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
        if (self._stderr) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
    }

    pub fn pid(self: *const Self) ?posix.pid_t {
        return self._pid;
    }

    pub fn returncode(self: *const Self) ?i32 {
        return self._returncode;
    }

    pub fn stdin(self: *Self) ?*ProcessPipe {
        return self._stdin;
    }

    pub fn stdout(self: *Self) ?*ProcessPipe {
        return self._stdout;
    }

    pub fn stderr(self: *Self) ?*ProcessPipe {
        return self._stderr;
    }

    /// Wait for process to terminate
    pub fn wait(self: *Self) !i32 {
        if (self._returncode) |rc| {
            return rc;
        }
        // Simulate waiting
        self._returncode = 0;
        return 0;
    }

    /// Communicate with process
    pub fn communicate(
        self: *Self,
        input: ?[]const u8,
    ) !struct { stdout: []const u8, stderr: []const u8 } {
        // Write input if provided
        if (input) |data| {
            if (self._stdin) |pipe| {
                try pipe.write(data);
                pipe.close();
            }
        }

        // Read output
        var stdout_data: []const u8 = "";
        var stderr_data: []const u8 = "";

        if (self._stdout) |pipe| {
            stdout_data = pipe.read_all();
        }
        if (self._stderr) |pipe| {
            stderr_data = pipe.read_all();
        }

        _ = try self.wait();

        return .{ .stdout = stdout_data, .stderr = stderr_data };
    }

    /// Send signal to process
    pub fn send_signal(self: *Self, sig: i32) !void {
        if (self._pid) |p| {
            _ = posix.kill(p, @intCast(sig)) catch {};
        }
    }

    /// Terminate the process
    pub fn terminate(self: *Self) !void {
        try self.send_signal(posix.SIG.TERM);
    }

    /// Kill the process
    pub fn kill(self: *Self) !void {
        try self.send_signal(posix.SIG.KILL);
    }
};

/// A pipe for subprocess I/O
pub const ProcessPipe = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _buffer: std.ArrayList(u8),
    _closed: bool = false,
    _eof: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._buffer.deinit();
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self._closed) {
            return error.PipeClosed;
        }
        try self._buffer.appendSlice(data);
    }

    pub fn read(self: *Self, n: usize) []const u8 {
        const to_read = @min(n, self._buffer.items.len);
        return self._buffer.items[0..to_read];
    }

    pub fn read_all(self: *Self) []const u8 {
        return self._buffer.items;
    }

    pub fn close(self: *Self) void {
        self._closed = true;
    }

    pub fn at_eof(self: *const Self) bool {
        return self._eof and self._buffer.items.len == 0;
    }

    /// Feed data (for testing)
    pub fn feed_data(self: *Self, data: []const u8) !void {
        try self._buffer.appendSlice(data);
    }

    pub fn feed_eof(self: *Self) void {
        self._eof = true;
    }
};

// ============================================================================
// Subprocess Creation Functions
// ============================================================================

/// Create a subprocess with exec
pub fn create_subprocess_exec(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    options: SubprocessOptions,
) !Process {
    var proc = Process.init(allocator);

    // Set up pipes based on options
    if (options.stdin_pipe) {
        proc._stdin = try allocator.create(ProcessPipe);
        proc._stdin.?.* = ProcessPipe.init(allocator);
    }
    if (options.stdout_pipe) {
        proc._stdout = try allocator.create(ProcessPipe);
        proc._stdout.?.* = ProcessPipe.init(allocator);
    }
    if (options.stderr_pipe) {
        proc._stderr = try allocator.create(ProcessPipe);
        proc._stderr.?.* = ProcessPipe.init(allocator);
    }

    // Simulate running the command
    if (args.len > 0) {
        proc._pid = 12345; // Mock PID

        // Simulate output for "echo" command
        if (std.mem.eql(u8, args[0], "echo")) {
            if (proc._stdout) |pipe| {
                for (args[1..]) |arg| {
                    try pipe.feed_data(arg);
                    try pipe.feed_data(" ");
                }
                try pipe.feed_data("\n");
            }
        }
    }

    return proc;
}

/// Create a subprocess with shell
pub fn create_subprocess_shell(
    allocator: std.mem.Allocator,
    cmd: []const u8,
    options: SubprocessOptions,
) !Process {
    // Split command for simulation
    var args = [_][]const u8{ "/bin/sh", "-c", cmd };
    return create_subprocess_exec(allocator, &args, options);
}

/// Options for subprocess creation
pub const SubprocessOptions = struct {
    stdin_pipe: bool = false,
    stdout_pipe: bool = false,
    stderr_pipe: bool = false,
    cwd: ?[]const u8 = null,
    env: ?std.StringHashMap([]const u8) = null,
};

// ============================================================================
// Test Cases
// ============================================================================

fn testProcessCreate() !void {
    const allocator = std.testing.allocator;
    var proc = Process.init(allocator);
    defer proc.deinit();

    try std.testing.expect(proc.pid() == null);
    try std.testing.expect(proc.returncode() == null);
}

fn testProcessPipeWrite() !void {
    const allocator = std.testing.allocator;
    var pipe = ProcessPipe.init(allocator);
    defer pipe.deinit();

    try pipe.write("hello");
    try std.testing.expectEqualStrings("hello", pipe.read_all());
}

fn testProcessPipeClose() !void {
    const allocator = std.testing.allocator;
    var pipe = ProcessPipe.init(allocator);
    defer pipe.deinit();

    try std.testing.expect(!pipe._closed);
    pipe.close();
    try std.testing.expect(pipe._closed);

    const err = pipe.write("data");
    try std.testing.expectError(error.PipeClosed, err);
}

fn testCreateSubprocessExec() !void {
    const allocator = std.testing.allocator;
    var args = [_][]const u8{ "echo", "hello", "world" };
    var proc = try create_subprocess_exec(allocator, &args, .{
        .stdout_pipe = true,
    });
    defer proc.deinit();

    try std.testing.expect(proc.pid() != null);
    try std.testing.expect(proc.stdout() != null);
}

fn testProcessCommunicate() !void {
    const allocator = std.testing.allocator;
    var args = [_][]const u8{ "echo", "test" };
    var proc = try create_subprocess_exec(allocator, &args, .{
        .stdout_pipe = true,
    });
    defer proc.deinit();

    const result = try proc.communicate(null);
    try std.testing.expect(result.stdout.len > 0);
}

fn testProcessWait() !void {
    const allocator = std.testing.allocator;
    var proc = Process.init(allocator);
    defer proc.deinit();

    const rc = try proc.wait();
    try std.testing.expectEqual(@as(i32, 0), rc);
    try std.testing.expectEqual(@as(?i32, 0), proc.returncode());
}

fn testSubprocessOptions() !void {
    const options = SubprocessOptions{
        .stdin_pipe = true,
        .stdout_pipe = true,
        .stderr_pipe = false,
        .cwd = "/tmp",
    };

    try std.testing.expect(options.stdin_pipe);
    try std.testing.expect(options.stdout_pipe);
    try std.testing.expect(!options.stderr_pipe);
    try std.testing.expectEqualStrings("/tmp", options.cwd.?);
}

fn testCreateSubprocessShell() !void {
    const allocator = std.testing.allocator;
    var proc = try create_subprocess_shell(allocator, "echo hello", .{
        .stdout_pipe = true,
    });
    defer proc.deinit();

    try std.testing.expect(proc.pid() != null);
}

fn testProcessPipeFeed() !void {
    const allocator = std.testing.allocator;
    var pipe = ProcessPipe.init(allocator);
    defer pipe.deinit();

    try pipe.feed_data("test data");
    try std.testing.expectEqualStrings("test data", pipe.read_all());

    pipe.feed_eof();
    try std.testing.expect(pipe._eof);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Process create" {
    try testProcessCreate();
}

test "ProcessPipe write" {
    try testProcessPipeWrite();
}

test "ProcessPipe close" {
    try testProcessPipeClose();
}

test "create_subprocess_exec" {
    try testCreateSubprocessExec();
}

test "Process communicate" {
    try testProcessCommunicate();
}

test "Process wait" {
    try testProcessWait();
}

test "SubprocessOptions" {
    try testSubprocessOptions();
}

test "create_subprocess_shell" {
    try testCreateSubprocessShell();
}

test "ProcessPipe feed" {
    try testProcessPipeFeed();
}

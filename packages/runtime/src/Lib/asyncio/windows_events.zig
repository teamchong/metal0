//! asyncio.windows_events - Windows-specific event loop
//! Reference: cpython/Lib/asyncio/windows_events.py

const std = @import("std");
const builtin = @import("builtin");
const base_events = @import("base_events.zig");
const proactor_events = @import("proactor_events.zig");
const selector_events = @import("selector_events.zig");
const protocols = @import("protocols.zig");
const transports = @import("transports.zig");

/// Windows selector event loop
/// CPython: class _WindowsSelectorEventLoop(selector_events.BaseSelectorEventLoop)
pub const WindowsSelectorEventLoop = struct {
    base: selector_events.BaseSelectorEventLoop,

    pub fn init(allocator: std.mem.Allocator) WindowsSelectorEventLoop {
        return .{
            .base = selector_events.BaseSelectorEventLoop.init(allocator),
        };
    }

    pub fn deinit(self: *WindowsSelectorEventLoop) void {
        self.base.deinit();
    }
};

/// Windows proactor event loop (recommended on Windows)
/// CPython: class ProactorEventLoop(proactor_events.BaseProactorEventLoop)
pub const ProactorEventLoop = struct {
    base: proactor_events.BaseProactorEventLoop,

    pub fn init(allocator: std.mem.Allocator) ProactorEventLoop {
        var proactor = proactor_events.IocpProactor.init(allocator);
        return .{
            .base = proactor_events.BaseProactorEventLoop.init(allocator, &proactor),
        };
    }

    pub fn deinit(self: *ProactorEventLoop) void {
        self.base.deinit();
    }

    /// Run until complete
    pub fn runUntilComplete(self: *ProactorEventLoop, future: anytype) !@TypeOf(future).ResultType {
        _ = self;
        return error.NotImplemented;
    }

    /// Run forever
    pub fn runForever(self: *ProactorEventLoop) !void {
        self.base.base.running = true;
        defer self.base.base.running = false;

        while (self.base.base.running) {
            try self.base.runOnce(null);
        }
    }

    /// Stop the loop
    pub fn stop(self: *ProactorEventLoop) void {
        self.base.base.running = false;
    }

    /// Check if loop is running
    pub fn isRunning(self: *ProactorEventLoop) bool {
        return self.base.base.running;
    }

    /// Check if loop is closed
    pub fn isClosed(self: *ProactorEventLoop) bool {
        return self.base.base.closed;
    }

    /// Close the loop
    pub fn close(self: *ProactorEventLoop) void {
        self.base.base.closed = true;
        if (self.base.proactor) |p| {
            p.close();
        }
    }
};

/// Windows event loop policy
/// CPython: class WindowsSelectorEventLoopPolicy(events.BaseDefaultEventLoopPolicy)
pub const WindowsSelectorEventLoopPolicy = struct {
    loop: ?*WindowsSelectorEventLoop,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WindowsSelectorEventLoopPolicy {
        return .{
            .loop = null,
            .allocator = allocator,
        };
    }

    pub fn getEventLoop(self: *WindowsSelectorEventLoopPolicy) !*WindowsSelectorEventLoop {
        if (self.loop == null) {
            self.loop = try self.allocator.create(WindowsSelectorEventLoop);
            self.loop.?.* = WindowsSelectorEventLoop.init(self.allocator);
        }
        return self.loop.?;
    }

    pub fn setEventLoop(self: *WindowsSelectorEventLoopPolicy, loop: ?*WindowsSelectorEventLoop) void {
        self.loop = loop;
    }

    pub fn newEventLoop(self: *WindowsSelectorEventLoopPolicy) !*WindowsSelectorEventLoop {
        const loop = try self.allocator.create(WindowsSelectorEventLoop);
        loop.* = WindowsSelectorEventLoop.init(self.allocator);
        return loop;
    }
};

/// Windows proactor event loop policy (recommended)
/// CPython: class WindowsProactorEventLoopPolicy(events.BaseDefaultEventLoopPolicy)
pub const WindowsProactorEventLoopPolicy = struct {
    loop: ?*ProactorEventLoop,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WindowsProactorEventLoopPolicy {
        return .{
            .loop = null,
            .allocator = allocator,
        };
    }

    pub fn getEventLoop(self: *WindowsProactorEventLoopPolicy) !*ProactorEventLoop {
        if (self.loop == null) {
            self.loop = try self.allocator.create(ProactorEventLoop);
            self.loop.?.* = ProactorEventLoop.init(self.allocator);
        }
        return self.loop.?;
    }

    pub fn setEventLoop(self: *WindowsProactorEventLoopPolicy, loop: ?*ProactorEventLoop) void {
        self.loop = loop;
    }

    pub fn newEventLoop(self: *WindowsProactorEventLoopPolicy) !*ProactorEventLoop {
        const loop = try self.allocator.create(ProactorEventLoop);
        loop.* = ProactorEventLoop.init(self.allocator);
        return loop;
    }
};

/// Pipe server for Windows named pipes
/// CPython: class PipeServer
pub const PipeServer = struct {
    address: []const u8,
    closed: bool,
    allocator: std.mem.Allocator,
    pending_accept: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator, address: []const u8) PipeServer {
        return .{
            .address = address,
            .closed = false,
            .allocator = allocator,
            .pending_accept = null,
        };
    }

    pub fn close(self: *PipeServer) void {
        self.closed = true;
    }

    pub fn isClosed(self: *PipeServer) bool {
        return self.closed;
    }
};

/// Subprocess stream protocol for Windows
/// CPython: class _WindowsSubprocessTransport(base_subprocess.BaseSubprocessTransport)
pub const WindowsSubprocessTransport = struct {
    pid: ?i32,
    returncode: ?i32,
    stdin: ?*proactor_events.ProactorWritePipeTransport,
    stdout: ?*proactor_events.ProactorReadPipeTransport,
    stderr: ?*proactor_events.ProactorReadPipeTransport,
    closed: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WindowsSubprocessTransport {
        return .{
            .pid = null,
            .returncode = null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .closed = false,
            .allocator = allocator,
        };
    }

    pub fn getPid(self: *WindowsSubprocessTransport) ?i32 {
        return self.pid;
    }

    pub fn getReturncode(self: *WindowsSubprocessTransport) ?i32 {
        return self.returncode;
    }

    pub fn getPipeTransport(self: *WindowsSubprocessTransport, fd: i32) ?*anyopaque {
        return switch (fd) {
            0 => if (self.stdin) |s| @ptrCast(s) else null,
            1 => if (self.stdout) |s| @ptrCast(s) else null,
            2 => if (self.stderr) |s| @ptrCast(s) else null,
            else => null,
        };
    }

    pub fn close(self: *WindowsSubprocessTransport) void {
        self.closed = true;
    }

    pub fn kill(self: *WindowsSubprocessTransport) void {
        // Would terminate process
        _ = self;
    }

    pub fn terminate(self: *WindowsSubprocessTransport) void {
        // Would terminate process gracefully
        _ = self;
    }

    pub fn sendSignal(self: *WindowsSubprocessTransport, signal: i32) void {
        _ = self;
        _ = signal;
    }
};

/// Check if we're on Windows
pub const is_windows = builtin.os.tag == .windows;

/// Default event loop policy for Windows
pub const DefaultEventLoopPolicy = if (is_windows)
    WindowsProactorEventLoopPolicy
else
    @compileError("Windows event loop only available on Windows");

// Tests
test "WindowsSelectorEventLoop creation" {
    const allocator = std.testing.allocator;

    var loop = WindowsSelectorEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.base.base.running);
}

test "ProactorEventLoop creation" {
    const allocator = std.testing.allocator;

    var loop = ProactorEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.isRunning());
    try std.testing.expect(!loop.isClosed());
}

test "PipeServer creation" {
    const allocator = std.testing.allocator;

    var server = PipeServer.init(allocator, "\\\\.\\pipe\\test");
    try std.testing.expect(!server.isClosed());

    server.close();
    try std.testing.expect(server.isClosed());
}

test "WindowsSubprocessTransport creation" {
    const allocator = std.testing.allocator;

    var transport = WindowsSubprocessTransport.init(allocator);
    try std.testing.expect(!transport.closed);
    try std.testing.expectEqual(@as(?i32, null), transport.getPid());

    transport.close();
    try std.testing.expect(transport.closed);
}

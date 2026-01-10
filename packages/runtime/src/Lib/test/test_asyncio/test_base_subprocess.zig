//! test.test_asyncio.test_base_subprocess - Tests for base subprocess support
//! Reference: cpython/Lib/test/test_asyncio/test_base_subprocess.py
//!
//! Tests for BaseSubprocessTransport and subprocess helpers

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");
const test_subprocess = @import("test_subprocess.zig");
const test_transports = @import("test_transports.zig");

// ============================================================================
// Base Subprocess Transport
// ============================================================================

/// Base transport for subprocess communication
pub const BaseSubprocessTransport = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _process: ?*test_subprocess.Process = null,
    _pid: ?posix.pid_t = null,
    _returncode: ?i32 = null,
    _closed: bool = false,
    _pipes: [3]?*test_subprocess.ProcessPipe,
    _protocol: ?*SubprocessProtocol = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._pipes = .{ null, null, null },
        };
    }

    pub fn deinit(self: *Self) void {
        for (&self._pipes) |*pipe| {
            if (pipe.*) |p| {
                p.deinit();
                self.allocator.destroy(p);
                pipe.* = null;
            }
        }
    }

    pub fn get_pid(self: *const Self) ?posix.pid_t {
        return self._pid;
    }

    pub fn get_returncode(self: *const Self) ?i32 {
        return self._returncode;
    }

    pub fn get_pipe_transport(self: *Self, fd: i32) ?*test_subprocess.ProcessPipe {
        if (fd >= 0 and fd < 3) {
            return self._pipes[@intCast(fd)];
        }
        return null;
    }

    pub fn kill(self: *Self) !void {
        if (self._pid) |pid| {
            _ = posix.kill(pid, posix.SIG.KILL) catch {};
        }
    }

    pub fn terminate(self: *Self) !void {
        if (self._pid) |pid| {
            _ = posix.kill(pid, posix.SIG.TERM) catch {};
        }
    }

    pub fn send_signal(self: *Self, sig: i32) !void {
        if (self._pid) |pid| {
            _ = posix.kill(pid, @intCast(sig)) catch {};
        }
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        for (&self._pipes) |*pipe| {
            if (pipe.*) |p| {
                p.close();
            }
        }
    }

    pub fn is_closing(self: *const Self) bool {
        return self._closed;
    }

    pub fn set_protocol(self: *Self, protocol: *SubprocessProtocol) void {
        self._protocol = protocol;
    }

    pub fn get_protocol(self: *const Self) ?*SubprocessProtocol {
        return self._protocol;
    }
};

// ============================================================================
// Subprocess Protocol
// ============================================================================

/// Protocol for subprocess communication
pub const SubprocessProtocol = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _transport: ?*BaseSubprocessTransport = null,
    _stdout_data: std.ArrayList(u8),
    _stderr_data: std.ArrayList(u8),
    _process_exited: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._stdout_data = std.ArrayList(u8).init(allocator),
            ._stderr_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._stdout_data.deinit();
        self._stderr_data.deinit();
    }

    pub fn connection_made(self: *Self, transport: *BaseSubprocessTransport) void {
        self._transport = transport;
    }

    pub fn connection_lost(self: *Self, _: ?anyerror) void {
        self._transport = null;
    }

    pub fn pipe_data_received(self: *Self, fd: i32, data: []const u8) !void {
        if (fd == 1) {
            try self._stdout_data.appendSlice(data);
        } else if (fd == 2) {
            try self._stderr_data.appendSlice(data);
        }
    }

    pub fn pipe_connection_lost(self: *Self, _: i32, _: ?anyerror) void {
        _ = self;
    }

    pub fn process_exited(self: *Self) void {
        self._process_exited = true;
    }
};

// ============================================================================
// Subprocess Helper Functions
// ============================================================================

/// Write to subprocess stdin
pub fn write_stdin(transport: *BaseSubprocessTransport, data: []const u8) !void {
    if (transport.get_pipe_transport(0)) |pipe| {
        try pipe.write(data);
    }
}

/// Close subprocess stdin
pub fn close_stdin(transport: *BaseSubprocessTransport) void {
    if (transport.get_pipe_transport(0)) |pipe| {
        pipe.close();
    }
}

/// Get subprocess stdout data
pub fn get_stdout(protocol: *SubprocessProtocol) []const u8 {
    return protocol._stdout_data.items;
}

/// Get subprocess stderr data
pub fn get_stderr(protocol: *SubprocessProtocol) []const u8 {
    return protocol._stderr_data.items;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testBaseSubprocessTransport() !void {
    const allocator = std.testing.allocator;
    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(transport.get_pid() == null);
    try std.testing.expect(transport.get_returncode() == null);
    try std.testing.expect(!transport.is_closing());
}

fn testBaseSubprocessTransportClose() !void {
    const allocator = std.testing.allocator;
    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    transport.close();
    try std.testing.expect(transport.is_closing());
}

fn testSubprocessProtocol() !void {
    const allocator = std.testing.allocator;
    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    try std.testing.expect(!proto._process_exited);
    proto.process_exited();
    try std.testing.expect(proto._process_exited);
}

fn testSubprocessProtocolData() !void {
    const allocator = std.testing.allocator;
    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    try proto.pipe_data_received(1, "stdout");
    try proto.pipe_data_received(2, "stderr");

    try std.testing.expectEqualStrings("stdout", get_stdout(&proto));
    try std.testing.expectEqualStrings("stderr", get_stderr(&proto));
}

fn testSubprocessProtocolConnection() !void {
    const allocator = std.testing.allocator;
    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    proto.connection_made(&transport);
    try std.testing.expect(proto._transport == &transport);

    proto.connection_lost(null);
    try std.testing.expect(proto._transport == null);
}

fn testTransportProtocol() !void {
    const allocator = std.testing.allocator;
    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    transport.set_protocol(&proto);
    try std.testing.expect(transport.get_protocol() == &proto);
}

fn testGetPipeTransport() !void {
    const allocator = std.testing.allocator;
    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    // No pipes set, should return null
    try std.testing.expect(transport.get_pipe_transport(0) == null);
    try std.testing.expect(transport.get_pipe_transport(1) == null);
    try std.testing.expect(transport.get_pipe_transport(2) == null);
    try std.testing.expect(transport.get_pipe_transport(3) == null);
}

fn testPipeConnectionLost() !void {
    const allocator = std.testing.allocator;
    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    // Should not crash
    proto.pipe_connection_lost(1, null);
    proto.pipe_connection_lost(2, error.SomeError);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "BaseSubprocessTransport" {
    try testBaseSubprocessTransport();
}

test "BaseSubprocessTransport close" {
    try testBaseSubprocessTransportClose();
}

test "SubprocessProtocol" {
    try testSubprocessProtocol();
}

test "SubprocessProtocol data" {
    try testSubprocessProtocolData();
}

test "SubprocessProtocol connection" {
    try testSubprocessProtocolConnection();
}

test "Transport protocol" {
    try testTransportProtocol();
}

test "get_pipe_transport" {
    try testGetPipeTransport();
}

test "pipe_connection_lost" {
    try testPipeConnectionLost();
}

const SomeError = error{SomeError};

//! asyncio.base_subprocess - Base subprocess transport
//! Reference: cpython/Lib/asyncio/base_subprocess.py

const std = @import("std");
const transports = @import("transports.zig");
const protocols = @import("protocols.zig");
const streams = @import("streams.zig");

/// Base subprocess transport implementation
/// CPython: class BaseSubprocessTransport(transports.SubprocessTransport)
pub const BaseSubprocessTransport = struct {
    base: transports.SubprocessTransport,
    protocol: ?*protocols.SubprocessProtocol,
    stdin: ?*streams.StreamWriter,
    stdout: ?*streams.StreamReader,
    stderr: ?*streams.StreamReader,
    closed: bool,

    pub fn init(allocator: std.mem.Allocator) BaseSubprocessTransport {
        return .{
            .base = transports.SubprocessTransport.init(allocator),
            .protocol = null,
            .stdin = null,
            .stdout = null,
            .stderr = null,
            .closed = false,
        };
    }

    pub fn deinit(self: *BaseSubprocessTransport) void {
        self.base.deinit();
    }

    /// Get pipe transport for given fd
    pub fn getPipeTransport(self: *BaseSubprocessTransport, fd: i32) ?*anyopaque {
        return switch (fd) {
            0 => if (self.stdin) |s| @ptrCast(s) else null,
            1 => if (self.stdout) |s| @ptrCast(s) else null,
            2 => if (self.stderr) |s| @ptrCast(s) else null,
            else => null,
        };
    }

    /// Close the transport
    pub fn close(self: *BaseSubprocessTransport) void {
        if (self.closed) return;
        self.closed = true;
        self.base.base.close();
    }

    /// Kill the subprocess
    pub fn kill(self: *BaseSubprocessTransport) void {
        self.base.kill();
    }

    /// Terminate the subprocess
    pub fn terminate(self: *BaseSubprocessTransport) void {
        self.base.terminate();
    }
};

/// Write stdin pipe transport
/// CPython: class WriteSubprocessPipeProto(protocols.BaseProtocol)
pub const WriteSubprocessPipeProto = struct {
    transport: ?*BaseSubprocessTransport,
    fd: i32,
    pipe: ?*streams.StreamWriter,
    connected: bool,

    pub fn init(transport: ?*BaseSubprocessTransport, fd: i32) WriteSubprocessPipeProto {
        return .{
            .transport = transport,
            .fd = fd,
            .pipe = null,
            .connected = false,
        };
    }

    pub fn connectionMade(self: *WriteSubprocessPipeProto, pipe: *streams.StreamWriter) void {
        self.pipe = pipe;
        self.connected = true;
    }

    pub fn connectionLost(self: *WriteSubprocessPipeProto) void {
        self.connected = false;
        self.pipe = null;
    }
};

/// Read stdout/stderr pipe transport
/// CPython: class ReadSubprocessPipeProto(WriteSubprocessPipeProto)
pub const ReadSubprocessPipeProto = struct {
    base: WriteSubprocessPipeProto,
    reader: ?*streams.StreamReader,

    pub fn init(transport: ?*BaseSubprocessTransport, fd: i32) ReadSubprocessPipeProto {
        return .{
            .base = WriteSubprocessPipeProto.init(transport, fd),
            .reader = null,
        };
    }

    pub fn dataReceived(self: *ReadSubprocessPipeProto, data: []const u8) !void {
        if (self.reader) |r| {
            try r.feedData(data);
        }
    }

    pub fn eofReceived(self: *ReadSubprocessPipeProto) void {
        if (self.reader) |r| {
            r.feedEof();
        }
    }
};

// Tests
test "BaseSubprocessTransport creation" {
    const allocator = std.testing.allocator;

    var transport = BaseSubprocessTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(!transport.closed);
    transport.close();
    try std.testing.expect(transport.closed);
}

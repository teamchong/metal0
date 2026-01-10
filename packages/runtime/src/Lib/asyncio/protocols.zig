//! asyncio.protocols - Protocol interfaces
//! Reference: cpython/Lib/asyncio/protocols.py

const std = @import("std");

/// Base protocol interface
/// CPython: class BaseProtocol
pub const BaseProtocol = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        connection_made: *const fn (*BaseProtocol, *anyopaque) void,
        connection_lost: *const fn (*BaseProtocol, ?anyerror) void,
        pause_writing: *const fn (*BaseProtocol) void,
        resume_writing: *const fn (*BaseProtocol) void,
    };

    /// Called when a connection is made
    pub fn connectionMade(self: *BaseProtocol, transport: *anyopaque) void {
        self.vtable.connection_made(self, transport);
    }

    /// Called when the connection is lost or closed
    pub fn connectionLost(self: *BaseProtocol, exc: ?anyerror) void {
        self.vtable.connection_lost(self, exc);
    }

    /// Called when the transport's buffer goes over the high-water mark
    pub fn pauseWriting(self: *BaseProtocol) void {
        self.vtable.pause_writing(self);
    }

    /// Called when the transport's buffer drains below the low-water mark
    pub fn resumeWriting(self: *BaseProtocol) void {
        self.vtable.resume_writing(self);
    }
};

/// Protocol for stream transports (TCP, Unix sockets)
/// CPython: class Protocol(BaseProtocol)
pub const Protocol = struct {
    base: BaseProtocol,
    data_received: *const fn (*Protocol, []const u8) void,
    eof_received: *const fn (*Protocol) bool,

    pub fn dataReceived(self: *Protocol, data: []const u8) void {
        self.data_received(self, data);
    }

    pub fn eofReceived(self: *Protocol) bool {
        return self.eof_received(self);
    }
};

/// Protocol with manual buffer control
/// CPython: class BufferedProtocol(BaseProtocol)
pub const BufferedProtocol = struct {
    base: BaseProtocol,
    get_buffer: *const fn (*BufferedProtocol, usize) []u8,
    buffer_updated: *const fn (*BufferedProtocol, usize) void,
    eof_received: *const fn (*BufferedProtocol) bool,

    pub fn getBuffer(self: *BufferedProtocol, sizehint: usize) []u8 {
        return self.get_buffer(self, sizehint);
    }

    pub fn bufferUpdated(self: *BufferedProtocol, nbytes: usize) void {
        self.buffer_updated(self, nbytes);
    }

    pub fn eofReceived(self: *BufferedProtocol) bool {
        return self.eof_received(self);
    }
};

/// Protocol for datagram (UDP) transports
/// CPython: class DatagramProtocol(BaseProtocol)
pub const DatagramProtocol = struct {
    base: BaseProtocol,
    datagram_received: *const fn (*DatagramProtocol, []const u8, std.net.Address) void,
    error_received: *const fn (*DatagramProtocol, anyerror) void,

    pub fn datagramReceived(self: *DatagramProtocol, data: []const u8, addr: std.net.Address) void {
        self.datagram_received(self, data, addr);
    }

    pub fn errorReceived(self: *DatagramProtocol, exc: anyerror) void {
        self.error_received(self, exc);
    }
};

/// Protocol for subprocess pipes
/// CPython: class SubprocessProtocol(BaseProtocol)
pub const SubprocessProtocol = struct {
    base: BaseProtocol,
    pipe_data_received: *const fn (*SubprocessProtocol, i32, []const u8) void,
    pipe_connection_lost: *const fn (*SubprocessProtocol, i32, ?anyerror) void,
    process_exited: *const fn (*SubprocessProtocol) void,

    pub fn pipeDataReceived(self: *SubprocessProtocol, fd: i32, data: []const u8) void {
        self.pipe_data_received(self, fd, data);
    }

    pub fn pipeConnectionLost(self: *SubprocessProtocol, fd: i32, exc: ?anyerror) void {
        self.pipe_connection_lost(self, fd, exc);
    }

    pub fn processExited(self: *SubprocessProtocol) void {
        self.process_exited(self);
    }
};

// Tests
test "BaseProtocol interface" {
    // Just verify the types compile correctly
    const BP = BaseProtocol;
    try std.testing.expect(@sizeOf(BP) > 0);
}

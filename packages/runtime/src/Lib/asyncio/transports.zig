//! asyncio.transports - Transport implementations
//! Reference: cpython/Lib/asyncio/transports.py

const std = @import("std");
const protocols = @import("protocols.zig");

/// Base transport interface
/// CPython: class BaseTransport
pub const BaseTransport = struct {
    extra_info: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    closed: bool,

    pub fn init(allocator: std.mem.Allocator) BaseTransport {
        return .{
            .extra_info = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
            .closed = false,
        };
    }

    pub fn deinit(self: *BaseTransport) void {
        self.extra_info.deinit();
    }

    /// Get optional transport information
    pub fn getExtraInfo(self: *BaseTransport, name: []const u8, default: ?[]const u8) ?[]const u8 {
        return self.extra_info.get(name) orelse default;
    }

    /// Check if transport is closing
    pub fn isClosing(self: *BaseTransport) bool {
        return self.closed;
    }

    /// Close the transport
    pub fn close(self: *BaseTransport) void {
        self.closed = true;
    }

    /// Set the protocol
    pub fn setProtocol(self: *BaseTransport, protocol: *protocols.BaseProtocol) void {
        _ = self;
        _ = protocol;
    }

    /// Get the protocol
    pub fn getProtocol(self: *BaseTransport) ?*protocols.BaseProtocol {
        _ = self;
        return null;
    }
};

/// Read-only transport interface
/// CPython: class ReadTransport(BaseTransport)
pub const ReadTransport = struct {
    base: BaseTransport,
    reading: bool,

    pub fn init(allocator: std.mem.Allocator) ReadTransport {
        return .{
            .base = BaseTransport.init(allocator),
            .reading = true,
        };
    }

    pub fn deinit(self: *ReadTransport) void {
        self.base.deinit();
    }

    /// Check if reading
    pub fn isReading(self: *ReadTransport) bool {
        return self.reading;
    }

    /// Pause the receiving end
    pub fn pauseReading(self: *ReadTransport) void {
        self.reading = false;
    }

    /// Resume the receiving end
    pub fn resumeReading(self: *ReadTransport) void {
        self.reading = true;
    }
};

/// Write-only transport interface
/// CPython: class WriteTransport(BaseTransport)
pub const WriteTransport = struct {
    base: BaseTransport,
    write_buffer: std.ArrayList(u8),
    write_buffer_size: usize,

    pub fn init(allocator: std.mem.Allocator) WriteTransport {
        return .{
            .base = BaseTransport.init(allocator),
            .write_buffer = .{},
            .write_buffer_size = 0,
        };
    }

    pub fn deinit(self: *WriteTransport) void {
        self.write_buffer.deinit(self.base.allocator);
        self.base.deinit();
    }

    /// Set the high and low water marks for write flow control
    pub fn setWriteBufferLimits(self: *WriteTransport, high: ?usize, low: ?usize) void {
        _ = self;
        _ = high;
        _ = low;
    }

    /// Get the high and low water marks for write flow control
    pub fn getWriteBufferLimits(self: *WriteTransport) struct { low: usize, high: usize } {
        _ = self;
        return .{ .low = 0, .high = 65536 };
    }

    /// Get the current size of the write buffer
    pub fn getWriteBufferSize(self: *WriteTransport) usize {
        return self.write_buffer_size;
    }

    /// Write data
    pub fn write(self: *WriteTransport, data: []const u8) !void {
        try self.write_buffer.appendSlice(self.base.allocator, data);
        self.write_buffer_size += data.len;
    }

    /// Write a list of data buffers
    pub fn writelines(self: *WriteTransport, list_of_data: []const []const u8) !void {
        for (list_of_data) |data| {
            try self.write(data);
        }
    }

    /// Close after flushing buffered data
    pub fn writeEof(self: *WriteTransport) void {
        self.base.closed = true;
    }

    /// Check if this transport supports write_eof
    pub fn canWriteEof(self: *WriteTransport) bool {
        _ = self;
        return true;
    }

    /// Abort the transport immediately
    pub fn abort(self: *WriteTransport) void {
        self.write_buffer.clearRetainingCapacity();
        self.write_buffer_size = 0;
        self.base.closed = true;
    }
};

/// Bidirectional transport (TCP connections)
/// CPython: class Transport(ReadTransport, WriteTransport)
pub const Transport = struct {
    read: ReadTransport,
    write: WriteTransport,

    pub fn init(allocator: std.mem.Allocator) Transport {
        return .{
            .read = ReadTransport.init(allocator),
            .write = WriteTransport.init(allocator),
        };
    }

    pub fn deinit(self: *Transport) void {
        self.read.deinit();
        self.write.deinit();
    }

    // Delegate to read transport
    pub fn isReading(self: *Transport) bool {
        return self.read.isReading();
    }

    pub fn pauseReading(self: *Transport) void {
        self.read.pauseReading();
    }

    pub fn resumeReading(self: *Transport) void {
        self.read.resumeReading();
    }

    // Delegate to write transport
    pub fn doWrite(self: *Transport, data: []const u8) !void {
        try self.write.write(data);
    }

    pub fn close(self: *Transport) void {
        self.read.base.close();
        self.write.base.close();
    }

    pub fn isClosing(self: *Transport) bool {
        return self.read.base.isClosing() or self.write.base.isClosing();
    }
};

/// Datagram (UDP) transport
/// CPython: class DatagramTransport(BaseTransport)
pub const DatagramTransport = struct {
    base: BaseTransport,

    pub fn init(allocator: std.mem.Allocator) DatagramTransport {
        return .{
            .base = BaseTransport.init(allocator),
        };
    }

    pub fn deinit(self: *DatagramTransport) void {
        self.base.deinit();
    }

    /// Send data to the remote end
    pub fn sendto(self: *DatagramTransport, data: []const u8, addr: ?std.net.Address) void {
        _ = self;
        _ = data;
        _ = addr;
    }

    /// Abort the transport immediately
    pub fn abort(self: *DatagramTransport) void {
        self.base.closed = true;
    }
};

/// Subprocess transport
/// CPython: class SubprocessTransport(BaseTransport)
pub const SubprocessTransport = struct {
    base: BaseTransport,
    pid: ?i32,
    returncode: ?i32,

    pub fn init(allocator: std.mem.Allocator) SubprocessTransport {
        return .{
            .base = BaseTransport.init(allocator),
            .pid = null,
            .returncode = null,
        };
    }

    pub fn deinit(self: *SubprocessTransport) void {
        self.base.deinit();
    }

    /// Get subprocess PID
    pub fn getPid(self: *SubprocessTransport) ?i32 {
        return self.pid;
    }

    /// Get subprocess return code
    pub fn getReturncode(self: *SubprocessTransport) ?i32 {
        return self.returncode;
    }

    /// Get pipe transport
    pub fn getPipeTransport(self: *SubprocessTransport, fd: i32) ?*Transport {
        _ = self;
        _ = fd;
        return null;
    }

    /// Send signal to subprocess
    pub fn sendSignal(self: *SubprocessTransport, signal: i32) void {
        _ = self;
        _ = signal;
    }

    /// Terminate the subprocess
    pub fn terminate(self: *SubprocessTransport) void {
        self.sendSignal(15); // SIGTERM
    }

    /// Kill the subprocess
    pub fn kill(self: *SubprocessTransport) void {
        self.sendSignal(9); // SIGKILL
    }
};

// Tests
test "Transport creation" {
    const allocator = std.testing.allocator;

    var transport = Transport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(!transport.isClosing());
    try std.testing.expect(transport.isReading());

    transport.pauseReading();
    try std.testing.expect(!transport.isReading());

    transport.close();
    try std.testing.expect(transport.isClosing());
}

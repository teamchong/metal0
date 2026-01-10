//! test.test_asyncio.test_protocols - Tests for asyncio protocols
//! Reference: cpython/Lib/test/test_asyncio/test_protocols.py
//!
//! Tests for Protocol, DatagramProtocol, SubprocessProtocol interfaces

const std = @import("std");
const utils = @import("utils.zig");

// ============================================================================
// Protocol Interfaces
// ============================================================================

/// Base protocol interface
pub const BaseProtocol = struct {
    const Self = @This();

    vtable: *const VTable,
    _transport: ?*anyopaque = null,

    pub const VTable = struct {
        connection_made: *const fn (*Self, *anyopaque) void,
        connection_lost: *const fn (*Self, ?anyerror) void,
        pause_writing: *const fn (*Self) void,
        resume_writing: *const fn (*Self) void,
    };

    pub fn connection_made(self: *Self, transport: *anyopaque) void {
        self._transport = transport;
        self.vtable.connection_made(self, transport);
    }

    pub fn connection_lost(self: *Self, exc: ?anyerror) void {
        self.vtable.connection_lost(self, exc);
        self._transport = null;
    }

    pub fn pause_writing(self: *Self) void {
        self.vtable.pause_writing(self);
    }

    pub fn resume_writing(self: *Self) void {
        self.vtable.resume_writing(self);
    }
};

/// Stream protocol (TCP)
pub const Protocol = struct {
    const Self = @This();

    base: BaseProtocol,
    _data_received: std.ArrayList(u8),
    _eof_received: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = .{
                .vtable = &default_vtable,
            },
            ._data_received = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self._data_received.deinit();
    }

    pub fn data_received(self: *Self, data: []const u8) !void {
        try self._data_received.appendSlice(data);
    }

    pub fn eof_received(self: *Self) bool {
        self._eof_received = true;
        return false; // Don't keep connection open
    }

    pub fn get_received_data(self: *const Self) []const u8 {
        return self._data_received.items;
    }

    const default_vtable = BaseProtocol.VTable{
        .connection_made = defaultConnectionMade,
        .connection_lost = defaultConnectionLost,
        .pause_writing = defaultPauseWriting,
        .resume_writing = defaultResumeWriting,
    };

    fn defaultConnectionMade(_: *BaseProtocol, _: *anyopaque) void {}
    fn defaultConnectionLost(_: *BaseProtocol, _: ?anyerror) void {}
    fn defaultPauseWriting(_: *BaseProtocol) void {}
    fn defaultResumeWriting(_: *BaseProtocol) void {}
};

/// Datagram protocol (UDP)
pub const DatagramProtocol = struct {
    const Self = @This();

    base: BaseProtocol,
    _datagrams: std.ArrayList(Datagram),
    _errors: std.ArrayList(anyerror),
    allocator: std.mem.Allocator,

    pub const Datagram = struct {
        data: []const u8,
        addr: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = .{
                .vtable = &default_vtable,
            },
            ._datagrams = std.ArrayList(Datagram).init(allocator),
            ._errors = std.ArrayList(anyerror).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self._datagrams.deinit();
        self._errors.deinit();
    }

    pub fn datagram_received(self: *Self, data: []const u8, addr: ?[]const u8) !void {
        try self._datagrams.append(.{ .data = data, .addr = addr });
    }

    pub fn error_received(self: *Self, exc: anyerror) !void {
        try self._errors.append(exc);
    }

    pub fn get_datagrams(self: *const Self) []const Datagram {
        return self._datagrams.items;
    }

    const default_vtable = BaseProtocol.VTable{
        .connection_made = defaultConnectionMade,
        .connection_lost = defaultConnectionLost,
        .pause_writing = defaultPauseWriting,
        .resume_writing = defaultResumeWriting,
    };

    fn defaultConnectionMade(_: *BaseProtocol, _: *anyopaque) void {}
    fn defaultConnectionLost(_: *BaseProtocol, _: ?anyerror) void {}
    fn defaultPauseWriting(_: *BaseProtocol) void {}
    fn defaultResumeWriting(_: *BaseProtocol) void {}
};

/// Subprocess protocol
pub const SubprocessProtocol = struct {
    const Self = @This();

    base: BaseProtocol,
    _stdout_data: std.ArrayList(u8),
    _stderr_data: std.ArrayList(u8),
    _process_exited: bool = false,
    _returncode: ?i32 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = .{
                .vtable = &default_vtable,
            },
            ._stdout_data = std.ArrayList(u8).init(allocator),
            ._stderr_data = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self._stdout_data.deinit();
        self._stderr_data.deinit();
    }

    pub fn pipe_data_received(self: *Self, fd: i32, data: []const u8) !void {
        if (fd == 1) { // stdout
            try self._stdout_data.appendSlice(data);
        } else if (fd == 2) { // stderr
            try self._stderr_data.appendSlice(data);
        }
    }

    pub fn pipe_connection_lost(self: *Self, fd: i32, exc: ?anyerror) void {
        _ = fd;
        _ = exc;
        _ = self;
    }

    pub fn process_exited(self: *Self, returncode: i32) void {
        self._process_exited = true;
        self._returncode = returncode;
    }

    pub fn get_stdout(self: *const Self) []const u8 {
        return self._stdout_data.items;
    }

    pub fn get_stderr(self: *const Self) []const u8 {
        return self._stderr_data.items;
    }

    const default_vtable = BaseProtocol.VTable{
        .connection_made = defaultConnectionMade,
        .connection_lost = defaultConnectionLost,
        .pause_writing = defaultPauseWriting,
        .resume_writing = defaultResumeWriting,
    };

    fn defaultConnectionMade(_: *BaseProtocol, _: *anyopaque) void {}
    fn defaultConnectionLost(_: *BaseProtocol, _: ?anyerror) void {}
    fn defaultPauseWriting(_: *BaseProtocol) void {}
    fn defaultResumeWriting(_: *BaseProtocol) void {}
};

/// Buffered protocol for flow control
pub const BufferedProtocol = struct {
    const Self = @This();

    base: BaseProtocol,
    _buffer: []u8,
    _buffer_size: usize,
    _paused: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !Self {
        return .{
            .base = .{
                .vtable = &default_vtable,
            },
            ._buffer = try allocator.alloc(u8, buffer_size),
            ._buffer_size = buffer_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self._buffer);
    }

    pub fn get_buffer(self: *Self, sizehint: usize) []u8 {
        _ = sizehint;
        return self._buffer;
    }

    pub fn buffer_updated(self: *Self, nbytes: usize) void {
        _ = nbytes;
        _ = self;
    }

    pub fn eof_received(self: *Self) bool {
        _ = self;
        return false;
    }

    const default_vtable = BaseProtocol.VTable{
        .connection_made = defaultConnectionMade,
        .connection_lost = defaultConnectionLost,
        .pause_writing = defaultPauseWriting,
        .resume_writing = defaultResumeWriting,
    };

    fn defaultConnectionMade(_: *BaseProtocol, _: *anyopaque) void {}
    fn defaultConnectionLost(_: *BaseProtocol, _: ?anyerror) void {}
    fn defaultPauseWriting(_: *BaseProtocol) void {}
    fn defaultResumeWriting(_: *BaseProtocol) void {}
};

// ============================================================================
// Test Cases
// ============================================================================

fn testProtocolBasic() !void {
    const allocator = std.testing.allocator;
    var proto = Protocol.init(allocator);
    defer proto.deinit();

    try proto.data_received("hello");
    try std.testing.expectEqualStrings("hello", proto.get_received_data());
}

fn testProtocolEof() !void {
    const allocator = std.testing.allocator;
    var proto = Protocol.init(allocator);
    defer proto.deinit();

    try std.testing.expect(!proto._eof_received);
    _ = proto.eof_received();
    try std.testing.expect(proto._eof_received);
}

fn testDatagramProtocol() !void {
    const allocator = std.testing.allocator;
    var proto = DatagramProtocol.init(allocator);
    defer proto.deinit();

    try proto.datagram_received("data1", "addr1");
    try proto.datagram_received("data2", "addr2");

    try std.testing.expectEqual(@as(usize, 2), proto.get_datagrams().len);
}

fn testDatagramProtocolError() !void {
    const allocator = std.testing.allocator;
    var proto = DatagramProtocol.init(allocator);
    defer proto.deinit();

    try proto.error_received(error.NetworkError);
    try std.testing.expectEqual(@as(usize, 1), proto._errors.items.len);
}

fn testSubprocessProtocol() !void {
    const allocator = std.testing.allocator;
    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    try proto.pipe_data_received(1, "stdout data");
    try proto.pipe_data_received(2, "stderr data");

    try std.testing.expectEqualStrings("stdout data", proto.get_stdout());
    try std.testing.expectEqualStrings("stderr data", proto.get_stderr());
}

fn testSubprocessProtocolExited() !void {
    const allocator = std.testing.allocator;
    var proto = SubprocessProtocol.init(allocator);
    defer proto.deinit();

    try std.testing.expect(!proto._process_exited);
    proto.process_exited(0);
    try std.testing.expect(proto._process_exited);
    try std.testing.expectEqual(@as(?i32, 0), proto._returncode);
}

fn testBufferedProtocol() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    const buf = proto.get_buffer(100);
    try std.testing.expectEqual(@as(usize, 1024), buf.len);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "Protocol basic" {
    try testProtocolBasic();
}

test "Protocol eof" {
    try testProtocolEof();
}

test "DatagramProtocol" {
    try testDatagramProtocol();
}

test "DatagramProtocol error" {
    try testDatagramProtocolError();
}

test "SubprocessProtocol" {
    try testSubprocessProtocol();
}

test "SubprocessProtocol exited" {
    try testSubprocessProtocolExited();
}

test "BufferedProtocol" {
    try testBufferedProtocol();
}

// Error types for testing
const NetworkError = error{NetworkError};

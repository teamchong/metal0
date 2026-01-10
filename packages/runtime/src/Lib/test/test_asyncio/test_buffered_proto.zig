//! test.test_asyncio.test_buffered_proto - Tests for buffered protocol
//! Reference: cpython/Lib/test/test_asyncio/test_buffered_proto.py
//!
//! Tests for BufferedProtocol with get_buffer/buffer_updated

const std = @import("std");
const utils = @import("utils.zig");
const test_protocols = @import("test_protocols.zig");
const test_transports = @import("test_transports.zig");

// ============================================================================
// Buffered Protocol Implementation
// ============================================================================

/// Protocol that uses a pre-allocated buffer for receiving data
pub const BufferedProtocol = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _buffer: []u8,
    _buffer_size: usize,
    _bytes_received: usize = 0,
    _eof: bool = false,
    _paused: bool = false,
    _transport: ?*test_transports.Transport = null,

    pub fn init(allocator: std.mem.Allocator, buffer_size: usize) !Self {
        return .{
            .allocator = allocator,
            ._buffer = try allocator.alloc(u8, buffer_size),
            ._buffer_size = buffer_size,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self._buffer);
    }

    /// Called when connection is established
    pub fn connection_made(self: *Self, transport: *test_transports.Transport) void {
        self._transport = transport;
    }

    /// Called when connection is lost
    pub fn connection_lost(self: *Self, _: ?anyerror) void {
        self._transport = null;
    }

    /// Get a buffer for receiving data
    pub fn get_buffer(self: *Self, sizehint: usize) []u8 {
        const available = self._buffer_size - self._bytes_received;
        const size = @min(sizehint, available);
        return self._buffer[self._bytes_received .. self._bytes_received + size];
    }

    /// Called when buffer has been updated with data
    pub fn buffer_updated(self: *Self, nbytes: usize) void {
        self._bytes_received += nbytes;
    }

    /// Called when EOF is received
    pub fn eof_received(self: *Self) bool {
        self._eof = true;
        return false;
    }

    /// Called to pause receiving
    pub fn pause_writing(self: *Self) void {
        self._paused = true;
    }

    /// Called to resume receiving
    pub fn resume_writing(self: *Self) void {
        self._paused = false;
    }

    /// Get all received data
    pub fn get_data(self: *const Self) []const u8 {
        return self._buffer[0..self._bytes_received];
    }

    /// Reset the buffer
    pub fn reset(self: *Self) void {
        self._bytes_received = 0;
        self._eof = false;
    }
};

// ============================================================================
// Buffered Stream Reader
// ============================================================================

/// Stream reader using buffered protocol
pub const BufferedStreamReader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _protocol: BufferedProtocol,
    _limit: usize,

    pub fn init(allocator: std.mem.Allocator, limit: usize) !Self {
        return .{
            .allocator = allocator,
            ._protocol = try BufferedProtocol.init(allocator, limit),
            ._limit = limit,
        };
    }

    pub fn deinit(self: *Self) void {
        self._protocol.deinit();
    }

    /// Feed data into the reader
    pub fn feed_data(self: *Self, data: []const u8) !void {
        const buf = self._protocol.get_buffer(data.len);
        if (buf.len < data.len) {
            return error.BufferFull;
        }
        @memcpy(buf[0..data.len], data);
        self._protocol.buffer_updated(data.len);
    }

    /// Get received data
    pub fn get_data(self: *const Self) []const u8 {
        return self._protocol.get_data();
    }

    /// Check if at EOF
    pub fn at_eof(self: *const Self) bool {
        return self._protocol._eof;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testBufferedProtocolCreate() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    try std.testing.expectEqual(@as(usize, 1024), proto._buffer_size);
    try std.testing.expectEqual(@as(usize, 0), proto._bytes_received);
}

fn testBufferedProtocolGetBuffer() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    const buf = proto.get_buffer(100);
    try std.testing.expectEqual(@as(usize, 100), buf.len);
}

fn testBufferedProtocolBufferUpdated() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    const buf = proto.get_buffer(100);
    @memcpy(buf[0..5], "hello");
    proto.buffer_updated(5);

    try std.testing.expectEqual(@as(usize, 5), proto._bytes_received);
    try std.testing.expectEqualStrings("hello", proto.get_data());
}

fn testBufferedProtocolEof() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    try std.testing.expect(!proto._eof);
    _ = proto.eof_received();
    try std.testing.expect(proto._eof);
}

fn testBufferedProtocolPause() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    try std.testing.expect(!proto._paused);
    proto.pause_writing();
    try std.testing.expect(proto._paused);
    proto.resume_writing();
    try std.testing.expect(!proto._paused);
}

fn testBufferedProtocolReset() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    const buf = proto.get_buffer(5);
    @memcpy(buf[0..5], "hello");
    proto.buffer_updated(5);
    _ = proto.eof_received();

    proto.reset();
    try std.testing.expectEqual(@as(usize, 0), proto._bytes_received);
    try std.testing.expect(!proto._eof);
}

fn testBufferedStreamReader() !void {
    const allocator = std.testing.allocator;
    var reader = try BufferedStreamReader.init(allocator, 1024);
    defer reader.deinit();

    try reader.feed_data("hello");
    try std.testing.expectEqualStrings("hello", reader.get_data());
}

fn testBufferedStreamReaderFull() !void {
    const allocator = std.testing.allocator;
    var reader = try BufferedStreamReader.init(allocator, 5);
    defer reader.deinit();

    try reader.feed_data("hello");
    const err = reader.feed_data("more");
    try std.testing.expectError(error.BufferFull, err);
}

fn testBufferedProtocolConnection() !void {
    const allocator = std.testing.allocator;
    var proto = try BufferedProtocol.init(allocator, 1024);
    defer proto.deinit();

    var transport = test_transports.Transport.init(allocator);
    defer transport.deinit();

    proto.connection_made(&transport);
    try std.testing.expect(proto._transport != null);

    proto.connection_lost(null);
    try std.testing.expect(proto._transport == null);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "BufferedProtocol create" {
    try testBufferedProtocolCreate();
}

test "BufferedProtocol get_buffer" {
    try testBufferedProtocolGetBuffer();
}

test "BufferedProtocol buffer_updated" {
    try testBufferedProtocolBufferUpdated();
}

test "BufferedProtocol eof" {
    try testBufferedProtocolEof();
}

test "BufferedProtocol pause" {
    try testBufferedProtocolPause();
}

test "BufferedProtocol reset" {
    try testBufferedProtocolReset();
}

test "BufferedStreamReader" {
    try testBufferedStreamReader();
}

test "BufferedStreamReader full" {
    try testBufferedStreamReaderFull();
}

test "BufferedProtocol connection" {
    try testBufferedProtocolConnection();
}

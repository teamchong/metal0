//! test.test_asyncio.test_streams - Tests for asyncio streams
//! Reference: cpython/Lib/test/test_asyncio/test_streams.py
//!
//! Tests for StreamReader, StreamWriter, and stream functions

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Stream Constants
// ============================================================================

/// Default buffer limit for streams
pub const DEFAULT_LIMIT: usize = 64 * 1024; // 64KB

// ============================================================================
// Stream Errors
// ============================================================================

pub const IncompleteReadError = error.IncompleteRead;
pub const LimitOverrunError = error.LimitOverrun;

// ============================================================================
// StreamReader Implementation
// ============================================================================

/// Async stream reader for buffered I/O
pub const StreamReader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _limit: usize,
    _buffer: std.ArrayList(u8),
    _eof: bool = false,
    _paused: bool = false,
    _exception: ?anyerror = null,
    _waiter: ?*test_events.Future = null,
    _transport: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, limit: usize) Self {
        return .{
            .allocator = allocator,
            ._limit = limit,
            ._buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._buffer.deinit();
    }

    /// Check if at EOF
    pub fn at_eof(self: *const Self) bool {
        return self._eof and self._buffer.items.len == 0;
    }

    /// Feed data into the stream
    pub fn feed_data(self: *Self, data: []const u8) !void {
        try self._buffer.appendSlice(data);
    }

    /// Signal EOF
    pub fn feed_eof(self: *Self) void {
        self._eof = true;
    }

    /// Set an exception
    pub fn set_exception(self: *Self, exc: anyerror) void {
        self._exception = exc;
    }

    /// Read up to n bytes
    pub fn read(self: *Self, n: usize) ![]const u8 {
        if (self._exception) |exc| {
            return exc;
        }

        if (n == 0) {
            return "";
        }

        const to_read = @min(n, self._buffer.items.len);
        if (to_read == 0) {
            if (self._eof) {
                return "";
            }
            // Would normally wait here
            return "";
        }

        // Copy and remove from buffer
        const result = try self.allocator.alloc(u8, to_read);
        @memcpy(result, self._buffer.items[0..to_read]);

        // Remove from front of buffer
        std.mem.copyForwards(
            u8,
            self._buffer.items[0 .. self._buffer.items.len - to_read],
            self._buffer.items[to_read..],
        );
        self._buffer.shrinkRetainingCapacity(self._buffer.items.len - to_read);

        return result;
    }

    /// Read exactly n bytes
    pub fn readexactly(self: *Self, n: usize) ![]const u8 {
        if (self._exception) |exc| {
            return exc;
        }

        if (self._buffer.items.len < n) {
            if (self._eof) {
                return IncompleteReadError;
            }
            // Would normally wait here
            return IncompleteReadError;
        }

        return self.read(n);
    }

    /// Read until separator
    pub fn readuntil(self: *Self, separator: []const u8) ![]const u8 {
        if (self._exception) |exc| {
            return exc;
        }

        // Find separator in buffer
        if (std.mem.indexOf(u8, self._buffer.items, separator)) |pos| {
            const end_pos = pos + separator.len;
            if (end_pos > self._limit) {
                return LimitOverrunError;
            }
            return self.read(end_pos);
        }

        if (self._buffer.items.len > self._limit) {
            return LimitOverrunError;
        }

        if (self._eof) {
            return IncompleteReadError;
        }

        // Would normally wait here
        return IncompleteReadError;
    }

    /// Read a line
    pub fn readline(self: *Self) ![]const u8 {
        return self.readuntil("\n");
    }
};

// ============================================================================
// StreamWriter Implementation
// ============================================================================

/// Async stream writer for buffered I/O
pub const StreamWriter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _buffer: std.ArrayList(u8),
    _closed: bool = false,
    _transport: ?*anyopaque = null,
    _drain_waiter: ?*test_events.Future = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._buffer.deinit();
    }

    /// Write data
    pub fn write(self: *Self, data: []const u8) !void {
        if (self._closed) {
            return error.ConnectionClosed;
        }
        try self._buffer.appendSlice(data);
    }

    /// Write multiple data segments
    pub fn writelines(self: *Self, lines: []const []const u8) !void {
        for (lines) |line| {
            try self.write(line);
        }
    }

    /// Drain the write buffer
    pub fn drain(self: *Self) !void {
        // In real implementation, this would wait for buffer to be sent
        _ = self;
    }

    /// Close the writer
    pub fn close(self: *Self) void {
        self._closed = true;
    }

    /// Wait for close to complete
    pub fn wait_closed(self: *Self) !void {
        // In real implementation, this would wait for transport to close
        _ = self;
    }

    /// Check if closing
    pub fn is_closing(self: *const Self) bool {
        return self._closed;
    }

    /// Get the written data (for testing)
    pub fn get_buffer(self: *const Self) []const u8 {
        return self._buffer.items;
    }
};

// ============================================================================
// StreamReaderProtocol
// ============================================================================

/// Protocol that feeds data to a StreamReader
pub const StreamReaderProtocol = struct {
    const Self = @This();

    _stream_reader: *StreamReader,
    _stream_writer: ?*StreamWriter = null,
    _closed: bool = false,

    pub fn init(reader: *StreamReader) Self {
        return .{
            ._stream_reader = reader,
        };
    }

    pub fn connection_made(self: *Self, transport: *anyopaque) void {
        self._stream_reader._transport = transport;
    }

    pub fn connection_lost(self: *Self, _: ?anyerror) void {
        self._stream_reader.feed_eof();
        self._closed = true;
    }

    pub fn data_received(self: *Self, data: []const u8) !void {
        try self._stream_reader.feed_data(data);
    }

    pub fn eof_received(self: *Self) void {
        self._stream_reader.feed_eof();
    }
};

// ============================================================================
// Stream Functions
// ============================================================================

/// Open a connection and return reader/writer pair
pub fn open_connection(
    allocator: std.mem.Allocator,
    _: []const u8,
    _: u16,
) !struct { reader: StreamReader, writer: StreamWriter } {
    return .{
        .reader = StreamReader.init(allocator, DEFAULT_LIMIT),
        .writer = StreamWriter.init(allocator),
    };
}

/// Start a server
pub const Server = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _serving: bool = false,
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn is_serving(self: *const Self) bool {
        return self._serving;
    }

    pub fn start_serving(self: *Self) void {
        self._serving = true;
    }

    pub fn close(self: *Self) void {
        self._serving = false;
        self._closed = true;
    }

    pub fn wait_closed(self: *Self) !void {
        _ = self;
    }
};

pub fn start_server(
    allocator: std.mem.Allocator,
    _: *const fn (*StreamReader, *StreamWriter) void,
    _: []const u8,
    _: u16,
) !Server {
    return Server.init(allocator);
}

// ============================================================================
// Test Cases
// ============================================================================

fn testStreamReaderBasic() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    try std.testing.expect(!reader.at_eof());
    try std.testing.expectEqual(@as(usize, 0), reader._buffer.items.len);
}

fn testStreamReaderFeedData() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    try reader.feed_data("hello");
    try std.testing.expectEqual(@as(usize, 5), reader._buffer.items.len);

    try reader.feed_data(" world");
    try std.testing.expectEqual(@as(usize, 11), reader._buffer.items.len);
}

fn testStreamReaderFeedEof() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    try std.testing.expect(!reader._eof);
    reader.feed_eof();
    try std.testing.expect(reader._eof);
}

fn testStreamReaderRead() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    try reader.feed_data("hello world");

    const data = try reader.read(5);
    defer allocator.free(data);

    try std.testing.expectEqualStrings("hello", data);
    try std.testing.expectEqual(@as(usize, 6), reader._buffer.items.len);
}

fn testStreamReaderAtEof() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    try reader.feed_data("data");
    reader.feed_eof();

    try std.testing.expect(!reader.at_eof()); // Still has data

    const data = try reader.read(4);
    defer allocator.free(data);

    try std.testing.expect(reader.at_eof()); // Now truly at EOF
}

fn testStreamWriterBasic() !void {
    const allocator = std.testing.allocator;
    var writer = StreamWriter.init(allocator);
    defer writer.deinit();

    try writer.write("hello");
    try std.testing.expectEqualStrings("hello", writer.get_buffer());
}

fn testStreamWriterWritelines() !void {
    const allocator = std.testing.allocator;
    var writer = StreamWriter.init(allocator);
    defer writer.deinit();

    var lines = [_][]const u8{ "line1\n", "line2\n", "line3\n" };
    try writer.writelines(&lines);

    try std.testing.expectEqualStrings("line1\nline2\nline3\n", writer.get_buffer());
}

fn testStreamWriterClose() !void {
    const allocator = std.testing.allocator;
    var writer = StreamWriter.init(allocator);
    defer writer.deinit();

    try std.testing.expect(!writer.is_closing());
    writer.close();
    try std.testing.expect(writer.is_closing());

    const err = writer.write("data");
    try std.testing.expectError(error.ConnectionClosed, err);
}

fn testServerBasic() !void {
    const allocator = std.testing.allocator;
    var server = Server.init(allocator);

    try std.testing.expect(!server.is_serving());
    server.start_serving();
    try std.testing.expect(server.is_serving());
    server.close();
    try std.testing.expect(!server.is_serving());
}

fn testStreamReaderProtocol() !void {
    const allocator = std.testing.allocator;
    var reader = StreamReader.init(allocator, DEFAULT_LIMIT);
    defer reader.deinit();

    var proto = StreamReaderProtocol.init(&reader);

    try proto.data_received("hello");
    try std.testing.expectEqual(@as(usize, 5), reader._buffer.items.len);

    proto.eof_received();
    try std.testing.expect(reader._eof);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "StreamReader basic" {
    try testStreamReaderBasic();
}

test "StreamReader feed_data" {
    try testStreamReaderFeedData();
}

test "StreamReader feed_eof" {
    try testStreamReaderFeedEof();
}

test "StreamReader read" {
    try testStreamReaderRead();
}

test "StreamReader at_eof" {
    try testStreamReaderAtEof();
}

test "StreamWriter basic" {
    try testStreamWriterBasic();
}

test "StreamWriter writelines" {
    try testStreamWriterWritelines();
}

test "StreamWriter close" {
    try testStreamWriterClose();
}

test "Server basic" {
    try testServerBasic();
}

test "StreamReaderProtocol" {
    try testStreamReaderProtocol();
}

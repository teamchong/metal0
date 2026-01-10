//! test.test_memoryio - Memory I/O Tests
//!
//! Tests for in-memory file-like objects: BytesIO and StringIO.
//! Covers read, write, seek, truncate, and buffer management.
//!
//! CPython equivalent: test_memoryio.py

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// BytesIO - Binary In-Memory Stream
// ============================================================================

/// In-memory binary stream (like Python's io.BytesIO)
pub const BytesIO = struct {
    const Self = @This();

    allocator: Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    position: usize,
    closed: bool,
    name: ?[]const u8,

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .position = 0,
            .closed = false,
            .name = null,
        };
    }

    pub fn initWithData(allocator: Allocator, data: []const u8) !Self {
        var self = init(allocator);
        try self.buffer.appendSlice(self.allocator, data);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Write bytes to the stream
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.closed) return error.StreamClosed;

        // Extend buffer if writing beyond current size
        const end_pos = self.position + data.len;
        if (end_pos > self.buffer.items.len) {
            try self.buffer.resize(self.allocator, end_pos);
        }

        // Copy data
        @memcpy(self.buffer.items[self.position..end_pos], data);
        self.position = end_pos;

        return data.len;
    }

    /// Write a single byte
    pub fn writeByte(self: *Self, byte: u8) !void {
        if (self.closed) return error.StreamClosed;

        if (self.position >= self.buffer.items.len) {
            try self.buffer.append(self.allocator, byte);
        } else {
            self.buffer.items[self.position] = byte;
        }
        self.position += 1;
    }

    /// Read bytes from the stream
    pub fn read(self: *Self, buf: []u8) !usize {
        if (self.closed) return error.StreamClosed;

        const available = self.buffer.items.len - self.position;
        const to_read = @min(buf.len, available);

        if (to_read == 0) return 0;

        @memcpy(buf[0..to_read], self.buffer.items[self.position .. self.position + to_read]);
        self.position += to_read;

        return to_read;
    }

    /// Read all remaining bytes
    pub fn readAll(self: *Self) ![]const u8 {
        if (self.closed) return error.StreamClosed;

        const result = self.buffer.items[self.position..];
        self.position = self.buffer.items.len;
        return result;
    }

    /// Read a single byte
    pub fn readByte(self: *Self) !?u8 {
        if (self.closed) return error.StreamClosed;

        if (self.position >= self.buffer.items.len) return null;

        const byte = self.buffer.items[self.position];
        self.position += 1;
        return byte;
    }

    /// Seek to position
    pub fn seek(self: *Self, offset: i64, whence: SeekWhence) !i64 {
        if (self.closed) return error.StreamClosed;

        const buf_len: i64 = @intCast(self.buffer.items.len);
        const cur_pos: i64 = @intCast(self.position);

        const new_pos: i64 = switch (whence) {
            .set => offset,
            .cur => cur_pos + offset,
            .end => buf_len + offset,
        };

        if (new_pos < 0) return error.InvalidSeek;

        self.position = @intCast(new_pos);
        return @intCast(self.position);
    }

    pub const SeekWhence = enum(u8) {
        set = 0,
        cur = 1,
        end = 2,
    };

    /// Get current position
    pub fn tell(self: *const Self) !usize {
        if (self.closed) return error.StreamClosed;
        return self.position;
    }

    /// Truncate to size
    pub fn truncate(self: *Self, size: ?usize) !usize {
        if (self.closed) return error.StreamClosed;

        const new_size = size orelse self.position;
        try self.buffer.resize(self.allocator, new_size);

        if (self.position > new_size) {
            self.position = new_size;
        }

        return new_size;
    }

    /// Get the entire buffer value
    pub fn getvalue(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Get buffer length
    pub fn len(self: *const Self) usize {
        return self.buffer.items.len;
    }

    /// Check if readable
    pub fn readable(self: *const Self) bool {
        return !self.closed;
    }

    /// Check if writable
    pub fn writable(self: *const Self) bool {
        return !self.closed;
    }

    /// Check if seekable
    pub fn seekable(self: *const Self) bool {
        return !self.closed;
    }

    /// Close the stream
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Check if closed
    pub fn isClosed(self: *const Self) bool {
        return self.closed;
    }

    /// Flush (no-op for memory stream)
    pub fn flush(_: *Self) !void {
        // No-op for in-memory stream
    }
};

// ============================================================================
// StringIO - Text In-Memory Stream
// ============================================================================

/// In-memory text stream (like Python's io.StringIO)
pub const StringIO = struct {
    const Self = @This();

    allocator: Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    position: usize,
    closed: bool,
    newline: NewlineMode,
    line_buffering: bool,

    pub const NewlineMode = enum {
        /// Universal newlines (default)
        universal,
        /// Preserve newlines as-is
        preserve,
        /// Translate to \n
        translate_lf,
        /// Translate to \r\n
        translate_crlf,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .position = 0,
            .closed = false,
            .newline = .universal,
            .line_buffering = false,
        };
    }

    pub fn initWithString(allocator: Allocator, s: []const u8) !Self {
        var self = init(allocator);
        try self.buffer.appendSlice(self.allocator, s);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Write string to the stream
    pub fn write(self: *Self, s: []const u8) !usize {
        if (self.closed) return error.StreamClosed;

        const end_pos = self.position + s.len;
        if (end_pos > self.buffer.items.len) {
            try self.buffer.resize(self.allocator, end_pos);
        }

        @memcpy(self.buffer.items[self.position..end_pos], s);
        self.position = end_pos;

        return s.len;
    }

    /// Read string from stream
    pub fn read(self: *Self, size: ?usize) ![]const u8 {
        if (self.closed) return error.StreamClosed;

        const available = self.buffer.items.len - self.position;
        const to_read = if (size) |s| @min(s, available) else available;

        if (to_read == 0) return "";

        const result = self.buffer.items[self.position .. self.position + to_read];
        self.position += to_read;

        return result;
    }

    /// Read a single line
    pub fn readline(self: *Self, limit: ?usize) ![]const u8 {
        if (self.closed) return error.StreamClosed;

        const max_len = limit orelse std.math.maxInt(usize);
        const start = self.position;
        var end = start;

        while (end < self.buffer.items.len and (end - start) < max_len) {
            if (self.buffer.items[end] == '\n') {
                end += 1;
                break;
            }
            end += 1;
        }

        const result = self.buffer.items[start..end];
        self.position = end;

        return result;
    }

    /// Read all lines
    pub fn readlines(self: *Self, allocator: Allocator) !std.ArrayListUnmanaged([]const u8) {
        if (self.closed) return error.StreamClosed;

        var lines: std.ArrayListUnmanaged([]const u8) = .{};
        while (self.position < self.buffer.items.len) {
            const line = try self.readline(null);
            if (line.len == 0) break;
            try lines.append(allocator, line);
        }
        return lines;
    }

    /// Seek to position
    pub fn seek(self: *Self, offset: i64, whence: BytesIO.SeekWhence) !i64 {
        if (self.closed) return error.StreamClosed;

        const buf_len: i64 = @intCast(self.buffer.items.len);
        const cur_pos: i64 = @intCast(self.position);

        const new_pos: i64 = switch (whence) {
            .set => offset,
            .cur => cur_pos + offset,
            .end => buf_len + offset,
        };

        if (new_pos < 0) return error.InvalidSeek;

        self.position = @intCast(new_pos);
        return @intCast(self.position);
    }

    /// Get current position
    pub fn tell(self: *const Self) !usize {
        if (self.closed) return error.StreamClosed;
        return self.position;
    }

    /// Truncate to size
    pub fn truncate(self: *Self, size: ?usize) !usize {
        if (self.closed) return error.StreamClosed;

        const new_size = size orelse self.position;
        try self.buffer.resize(self.allocator, new_size);

        if (self.position > new_size) {
            self.position = new_size;
        }

        return new_size;
    }

    /// Get the entire buffer value
    pub fn getvalue(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Close the stream
    pub fn close(self: *Self) void {
        self.closed = true;
    }
};

// ============================================================================
// Memory Stream Stats
// ============================================================================

/// Statistics for memory streams
pub const StreamStats = struct {
    bytes_written: u64 = 0,
    bytes_read: u64 = 0,
    write_calls: u64 = 0,
    read_calls: u64 = 0,
    seek_calls: u64 = 0,
    peak_size: usize = 0,

    pub fn recordWrite(self: *StreamStats, size: usize, current_size: usize) void {
        self.bytes_written += size;
        self.write_calls += 1;
        self.peak_size = @max(self.peak_size, current_size);
    }

    pub fn recordRead(self: *StreamStats, size: usize) void {
        self.bytes_read += size;
        self.read_calls += 1;
    }

    pub fn recordSeek(self: *StreamStats) void {
        self.seek_calls += 1;
    }
};

// ============================================================================
// Buffered Memory Stream
// ============================================================================

/// Memory stream with buffering
pub const BufferedMemoryStream = struct {
    const Self = @This();

    allocator: Allocator,
    base: BytesIO,
    read_buffer: std.ArrayListUnmanaged(u8),
    write_buffer: std.ArrayListUnmanaged(u8),
    buffer_size: usize,
    stats: StreamStats,

    pub fn init(allocator: Allocator, buffer_size: usize) Self {
        return .{
            .allocator = allocator,
            .base = BytesIO.init(allocator),
            .read_buffer = .{},
            .write_buffer = .{},
            .buffer_size = buffer_size,
            .stats = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
        self.read_buffer.deinit(self.allocator);
        self.write_buffer.deinit(self.allocator);
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        try self.write_buffer.appendSlice(self.allocator, data);
        self.stats.recordWrite(data.len, self.base.len());

        if (self.write_buffer.items.len >= self.buffer_size) {
            try self.flushWriteBuffer();
        }

        return data.len;
    }

    fn flushWriteBuffer(self: *Self) !void {
        if (self.write_buffer.items.len > 0) {
            _ = try self.base.write(self.write_buffer.items);
            self.write_buffer.clearRetainingCapacity();
        }
    }

    pub fn read(self: *Self, buf: []u8) !usize {
        try self.flushWriteBuffer();
        const read_count = try self.base.read(buf);
        self.stats.recordRead(read_count);
        return read_count;
    }

    pub fn flush(self: *Self) !void {
        try self.flushWriteBuffer();
    }

    pub fn getvalue(self: *Self) ![]const u8 {
        try self.flushWriteBuffer();
        return self.base.getvalue();
    }
};

// ============================================================================
// Stream Wrapper
// ============================================================================

/// Generic wrapper for stream operations
pub const StreamWrapper = struct {
    const Self = @This();

    stream_type: StreamType,
    bytes_io: ?*BytesIO,
    string_io: ?*StringIO,

    pub const StreamType = enum {
        bytes,
        string,
    };

    pub fn wrapBytes(io: *BytesIO) Self {
        return .{
            .stream_type = .bytes,
            .bytes_io = io,
            .string_io = null,
        };
    }

    pub fn wrapString(io: *StringIO) Self {
        return .{
            .stream_type = .string,
            .bytes_io = null,
            .string_io = io,
        };
    }

    pub fn getvalue(self: *const Self) []const u8 {
        return switch (self.stream_type) {
            .bytes => self.bytes_io.?.getvalue(),
            .string => self.string_io.?.getvalue(),
        };
    }

    pub fn len(self: *const Self) usize {
        return self.getvalue().len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "bytes_io_init" {
    const allocator = std.testing.allocator;
    var bio = BytesIO.init(allocator);
    defer bio.deinit();

    try std.testing.expectEqual(@as(usize, 0), bio.len());
    try std.testing.expect(!bio.closed);
}

test "bytes_io_init_with_data" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello");
    defer bio.deinit();

    try std.testing.expectEqual(@as(usize, 5), bio.len());
    try std.testing.expectEqualStrings("hello", bio.getvalue());
}

test "bytes_io_write" {
    const allocator = std.testing.allocator;
    var bio = BytesIO.init(allocator);
    defer bio.deinit();

    const written = try bio.write("hello");
    try std.testing.expectEqual(@as(usize, 5), written);
    try std.testing.expectEqualStrings("hello", bio.getvalue());
}

test "bytes_io_write_byte" {
    const allocator = std.testing.allocator;
    var bio = BytesIO.init(allocator);
    defer bio.deinit();

    try bio.writeByte('a');
    try bio.writeByte('b');
    try bio.writeByte('c');

    try std.testing.expectEqualStrings("abc", bio.getvalue());
}

test "bytes_io_read" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    var buf: [5]u8 = undefined;
    const read_count = try bio.read(&buf);

    try std.testing.expectEqual(@as(usize, 5), read_count);
    try std.testing.expectEqualStrings("hello", buf[0..5]);
}

test "bytes_io_read_all" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    const result = try bio.readAll();
    try std.testing.expectEqualStrings("hello world", result);
}

test "bytes_io_read_byte" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "abc");
    defer bio.deinit();

    try std.testing.expectEqual(@as(?u8, 'a'), try bio.readByte());
    try std.testing.expectEqual(@as(?u8, 'b'), try bio.readByte());
    try std.testing.expectEqual(@as(?u8, 'c'), try bio.readByte());
    try std.testing.expectEqual(@as(?u8, null), try bio.readByte());
}

test "bytes_io_seek_tell" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    _ = try bio.seek(6, .set);
    try std.testing.expectEqual(@as(usize, 6), try bio.tell());

    _ = try bio.seek(2, .cur);
    try std.testing.expectEqual(@as(usize, 8), try bio.tell());

    _ = try bio.seek(-3, .end);
    try std.testing.expectEqual(@as(usize, 8), try bio.tell());
}

test "bytes_io_truncate" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    _ = try bio.truncate(5);
    try std.testing.expectEqualStrings("hello", bio.getvalue());
}

test "bytes_io_truncate_at_position" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    _ = try bio.seek(5, .set);
    _ = try bio.truncate(null);
    try std.testing.expectEqualStrings("hello", bio.getvalue());
}

test "bytes_io_close" {
    const allocator = std.testing.allocator;
    var bio = BytesIO.init(allocator);
    defer bio.deinit();

    bio.close();
    try std.testing.expect(bio.isClosed());
    try std.testing.expectError(error.StreamClosed, bio.write("test"));
}

test "bytes_io_readable_writable" {
    const allocator = std.testing.allocator;
    var bio = BytesIO.init(allocator);
    defer bio.deinit();

    try std.testing.expect(bio.readable());
    try std.testing.expect(bio.writable());
    try std.testing.expect(bio.seekable());
}

test "string_io_init" {
    const allocator = std.testing.allocator;
    var sio = StringIO.init(allocator);
    defer sio.deinit();

    try std.testing.expectEqualStrings("", sio.getvalue());
}

test "string_io_init_with_string" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "hello");
    defer sio.deinit();

    try std.testing.expectEqualStrings("hello", sio.getvalue());
}

test "string_io_write" {
    const allocator = std.testing.allocator;
    var sio = StringIO.init(allocator);
    defer sio.deinit();

    _ = try sio.write("hello ");
    _ = try sio.write("world");

    try std.testing.expectEqualStrings("hello world", sio.getvalue());
}

test "string_io_read" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "hello world");
    defer sio.deinit();

    const result = try sio.read(5);
    try std.testing.expectEqualStrings("hello", result);
}

test "string_io_readline" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "line1\nline2\nline3");
    defer sio.deinit();

    try std.testing.expectEqualStrings("line1\n", try sio.readline(null));
    try std.testing.expectEqualStrings("line2\n", try sio.readline(null));
    try std.testing.expectEqualStrings("line3", try sio.readline(null));
}

test "string_io_readline_limit" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "hello world\n");
    defer sio.deinit();

    const result = try sio.readline(5);
    try std.testing.expectEqualStrings("hello", result);
}

test "string_io_readlines" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "a\nb\nc");
    defer sio.deinit();

    var lines = try sio.readlines(allocator);
    defer lines.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), lines.items.len);
}

test "string_io_seek" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "hello world");
    defer sio.deinit();

    _ = try sio.seek(6, .set);
    const result = try sio.read(null);
    try std.testing.expectEqualStrings("world", result);
}

test "string_io_truncate" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "hello world");
    defer sio.deinit();

    _ = try sio.truncate(5);
    try std.testing.expectEqualStrings("hello", sio.getvalue());
}

test "stream_stats_record" {
    var stats = StreamStats{};

    stats.recordWrite(100, 100);
    stats.recordWrite(50, 150);
    stats.recordRead(75);

    try std.testing.expectEqual(@as(u64, 150), stats.bytes_written);
    try std.testing.expectEqual(@as(u64, 75), stats.bytes_read);
    try std.testing.expectEqual(@as(u64, 2), stats.write_calls);
    try std.testing.expectEqual(@as(u64, 1), stats.read_calls);
    try std.testing.expectEqual(@as(usize, 150), stats.peak_size);
}

test "buffered_stream_write" {
    const allocator = std.testing.allocator;
    var stream = BufferedMemoryStream.init(allocator, 16);
    defer stream.deinit();

    _ = try stream.write("hello");
    try stream.flush();

    try std.testing.expectEqualStrings("hello", try stream.getvalue());
}

test "stream_wrapper_bytes" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "test");
    defer bio.deinit();

    const wrapper = StreamWrapper.wrapBytes(&bio);
    try std.testing.expectEqual(@as(usize, 4), wrapper.len());
}

test "stream_wrapper_string" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.initWithString(allocator, "test");
    defer sio.deinit();

    const wrapper = StreamWrapper.wrapString(&sio);
    try std.testing.expectEqual(@as(usize, 4), wrapper.len());
}

test "bytes_io_overwrite" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello");
    defer bio.deinit();

    _ = try bio.seek(0, .set);
    _ = try bio.write("HELLO");

    try std.testing.expectEqualStrings("HELLO", bio.getvalue());
}

test "bytes_io_partial_overwrite" {
    const allocator = std.testing.allocator;
    var bio = try BytesIO.initWithData(allocator, "hello world");
    defer bio.deinit();

    _ = try bio.seek(6, .set);
    _ = try bio.write("WORLD");

    try std.testing.expectEqualStrings("hello WORLD", bio.getvalue());
}

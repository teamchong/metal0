//! asyncio.streams - High-level stream API
//! Reference: cpython/Lib/asyncio/streams.py

const std = @import("std");
const futures = @import("futures.zig");
const transports = @import("transports.zig");
const protocols = @import("protocols.zig");
const exceptions = @import("exceptions.zig");

/// Default buffer limit for streams
pub const _DEFAULT_LIMIT: usize = 64 * 1024; // 64 KiB

/// StreamReader - async reader for stream data
/// CPython: class StreamReader
pub const StreamReader = struct {
    limit: usize,
    buffer: std.ArrayList(u8),
    eof: bool,
    waiter: ?*futures.Future(void),
    transport: ?*transports.Transport,
    paused: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, limit: usize) StreamReader {
        return .{
            .limit = if (limit == 0) _DEFAULT_LIMIT else limit,
            .buffer = .{},
            .eof = false,
            .waiter = null,
            .transport = null,
            .paused = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StreamReader) void {
        self.buffer.deinit(self.allocator);
    }

    /// Check if at end of stream
    pub fn atEof(self: *StreamReader) bool {
        return self.eof and self.buffer.items.len == 0;
    }

    /// Feed data to the internal buffer
    pub fn feedData(self: *StreamReader, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);

        // Wake any waiting reader
        if (self.waiter) |w| {
            w.resolve({});
            self.waiter = null;
        }

        // Pause if over limit
        if (self.buffer.items.len >= self.limit) {
            self.paused = true;
            if (self.transport) |t| {
                t.pauseReading();
            }
        }
    }

    /// Signal end of stream
    pub fn feedEof(self: *StreamReader) void {
        self.eof = true;
        if (self.waiter) |w| {
            w.resolve({});
            self.waiter = null;
        }
    }

    /// Read up to n bytes
    pub fn read(self: *StreamReader, n: i64) ![]u8 {
        // Wait for data if buffer empty
        while (self.buffer.items.len == 0 and !self.eof) {
            const waiter = try futures.Future(void).init(self.allocator);
            self.waiter = waiter;

            while (!waiter.isReady()) {
                std.Thread.sleep(1_000);
            }
            waiter.deinit();
        }

        if (self.buffer.items.len == 0) {
            return &[_]u8{};
        }

        const bytes_to_read: usize = if (n < 0)
            self.buffer.items.len
        else
            @min(@as(usize, @intCast(n)), self.buffer.items.len);

        const result = try self.allocator.alloc(u8, bytes_to_read);
        @memcpy(result, self.buffer.items[0..bytes_to_read]);

        // Remove read bytes from buffer
        const remaining = self.buffer.items.len - bytes_to_read;
        if (remaining > 0) {
            std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[bytes_to_read..]);
        }
        self.buffer.shrinkRetainingCapacity(remaining);

        // Resume reading if under limit
        if (self.paused and self.buffer.items.len < self.limit) {
            self.paused = false;
            if (self.transport) |t| {
                t.resumeReading();
            }
        }

        return result;
    }

    /// Read one line
    pub fn readline(self: *StreamReader) ![]u8 {
        return self.readuntil("\n");
    }

    /// Read until separator
    pub fn readuntil(self: *StreamReader, separator: []const u8) ![]u8 {
        // Wait for separator or EOF
        while (true) {
            if (std.mem.indexOf(u8, self.buffer.items, separator)) |pos| {
                const end = pos + separator.len;
                const result = try self.allocator.alloc(u8, end);
                @memcpy(result, self.buffer.items[0..end]);

                const remaining = self.buffer.items.len - end;
                if (remaining > 0) {
                    std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[end..]);
                }
                self.buffer.shrinkRetainingCapacity(remaining);

                return result;
            }

            if (self.eof) {
                // Return remaining buffer as incomplete read
                if (self.buffer.items.len > 0) {
                    const result = try self.allocator.alloc(u8, self.buffer.items.len);
                    @memcpy(result, self.buffer.items);
                    self.buffer.clearRetainingCapacity();
                    return result;
                }
                return &[_]u8{};
            }

            // Check limit
            if (self.buffer.items.len >= self.limit) {
                return exceptions.LimitOverrunError.init("separator not found", self.buffer.items.len);
            }

            // Wait for more data
            const waiter = try futures.Future(void).init(self.allocator);
            self.waiter = waiter;

            while (!waiter.isReady()) {
                std.Thread.sleep(1_000);
            }
            waiter.deinit();
        }
    }

    /// Read exactly n bytes
    pub fn readexactly(self: *StreamReader, n: usize) ![]u8 {
        while (self.buffer.items.len < n and !self.eof) {
            const waiter = try futures.Future(void).init(self.allocator);
            self.waiter = waiter;

            while (!waiter.isReady()) {
                std.Thread.sleep(1_000);
            }
            waiter.deinit();
        }

        if (self.buffer.items.len < n) {
            const partial = try self.allocator.alloc(u8, self.buffer.items.len);
            @memcpy(partial, self.buffer.items);
            return exceptions.IncompleteReadError.init(partial, n);
        }

        const result = try self.allocator.alloc(u8, n);
        @memcpy(result, self.buffer.items[0..n]);

        const remaining = self.buffer.items.len - n;
        if (remaining > 0) {
            std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[n..]);
        }
        self.buffer.shrinkRetainingCapacity(remaining);

        return result;
    }
};

/// StreamWriter - async writer for stream data
/// CPython: class StreamWriter
pub const StreamWriter = struct {
    transport: *transports.Transport,
    reader: ?*StreamReader,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, transport: *transports.Transport, reader: ?*StreamReader) StreamWriter {
        return .{
            .transport = transport,
            .reader = reader,
            .allocator = allocator,
        };
    }

    /// Write data to the transport
    pub fn write(self: *StreamWriter, data: []const u8) !void {
        try self.transport.doWrite(data);
    }

    /// Write multiple data chunks
    pub fn writelines(self: *StreamWriter, data: []const []const u8) !void {
        for (data) |chunk| {
            try self.write(chunk);
        }
    }

    /// Close the writer
    pub fn close(self: *StreamWriter) void {
        self.transport.close();
    }

    /// Check if writer is closing
    pub fn isClosing(self: *StreamWriter) bool {
        return self.transport.isClosing();
    }

    /// Wait until the transport is closed
    pub fn waitClosed(self: *StreamWriter) !void {
        while (!self.transport.isClosing()) {
            std.Thread.sleep(1_000);
        }
    }

    /// Wait until the write buffer is flushed
    pub fn drain(self: *StreamWriter) !void {
        while (self.transport.write.getWriteBufferSize() > 0) {
            std.Thread.sleep(1_000);
        }
    }

    /// Get extra info from transport
    pub fn getExtraInfo(self: *StreamWriter, name: []const u8, default: ?[]const u8) ?[]const u8 {
        return self.transport.read.base.getExtraInfo(name, default);
    }
};

/// Open a connection and return (reader, writer) pair
/// CPython: async def open_connection(host, port, ...)
pub fn openConnection(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
) !struct { reader: *StreamReader, writer: *StreamWriter } {
    _ = host;
    _ = port;

    // Create reader and writer
    const reader = try allocator.create(StreamReader);
    reader.* = StreamReader.init(allocator, _DEFAULT_LIMIT);

    const transport = try allocator.create(transports.Transport);
    transport.* = transports.Transport.init(allocator);

    const writer = try allocator.create(StreamWriter);
    writer.* = StreamWriter.init(allocator, transport, reader);

    return .{ .reader = reader, .writer = writer };
}

/// Start a socket server
/// CPython: async def start_server(client_connected_cb, host, port, ...)
pub fn startServer(
    allocator: std.mem.Allocator,
    client_cb: *const fn (*StreamReader, *StreamWriter) void,
    host: []const u8,
    port: u16,
) !void {
    _ = allocator;
    _ = client_cb;
    _ = host;
    _ = port;
    // Server implementation would go here
}

// Tests
test "StreamReader basic" {
    const allocator = std.testing.allocator;

    var reader = StreamReader.init(allocator, 0);
    defer reader.deinit();

    try std.testing.expect(!reader.atEof());

    try reader.feedData("hello");
    try std.testing.expectEqual(@as(usize, 5), reader.buffer.items.len);

    reader.feedEof();
    try std.testing.expect(!reader.atEof()); // Still has data

    const data = try reader.read(-1);
    defer allocator.free(data);
    try std.testing.expectEqualStrings("hello", data);

    try std.testing.expect(reader.atEof()); // Now empty and EOF
}

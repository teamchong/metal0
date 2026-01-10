//! compression._common._streams - Stream utilities for compression
//! Reference: cpython/Lib/_compression.py stream handling
//!
//! Internal module providing stream wrappers for compression/decompression.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default buffer size
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

/// Maximum chunk size for reading
pub const MAX_CHUNK_SIZE: usize = 1024 * 1024; // 1 MB

// ============================================================================
// BufferedReader
// ============================================================================

/// Buffered reader for compressed streams
pub const BufferedReader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Source reader
    source: std.fs.File,
    /// Read buffer
    buffer: std.ArrayList(u8),
    /// Current position in buffer
    pos: usize = 0,
    /// Whether EOF reached
    eof: bool = false,

    pub fn init(allocator: std.mem.Allocator, source: std.fs.File) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Read up to size bytes
    pub fn read(self: *Self, size: usize) ![]u8 {
        if (self.eof and self.pos >= self.buffer.items.len) {
            return self.allocator.alloc(u8, 0);
        }

        // Fill buffer if needed
        if (self.pos >= self.buffer.items.len) {
            var raw_buf: [DEFAULT_BUFFER_SIZE]u8 = undefined;
            const n = try self.source.read(&raw_buf);
            if (n == 0) {
                self.eof = true;
                return self.allocator.alloc(u8, 0);
            }
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, raw_buf[0..n]);
            self.pos = 0;
        }

        const available = self.buffer.items.len - self.pos;
        const to_read = @min(size, available);
        const result = try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return result;
    }

    /// Read all remaining data
    pub fn readAll(self: *Self) ![]u8 {
        var result: std.ArrayList(u8) = .{};

        while (!self.eof) {
            const chunk = try self.read(DEFAULT_BUFFER_SIZE);
            if (chunk.len == 0) break;
            try result.appendSlice(self.allocator, chunk);
            self.allocator.free(chunk);
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Peek at data without consuming
    pub fn peek(self: *Self, size: usize) ![]u8 {
        if (self.pos >= self.buffer.items.len and !self.eof) {
            var raw_buf: [DEFAULT_BUFFER_SIZE]u8 = undefined;
            const n = try self.source.read(&raw_buf);
            if (n == 0) {
                self.eof = true;
                return self.allocator.alloc(u8, 0);
            }
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, raw_buf[0..n]);
            self.pos = 0;
        }

        const available = self.buffer.items.len - self.pos;
        const to_peek = @min(size, available);
        return try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_peek]);
    }
};

// ============================================================================
// BufferedWriter
// ============================================================================

/// Buffered writer for compressed streams
pub const BufferedWriter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Destination writer
    dest: std.fs.File,
    /// Write buffer
    buffer: std.ArrayList(u8),
    /// Buffer flush threshold
    threshold: usize,

    pub fn init(allocator: std.mem.Allocator, dest: std.fs.File, threshold: usize) Self {
        return .{
            .allocator = allocator,
            .dest = dest,
            .buffer = .{},
            .threshold = if (threshold == 0) DEFAULT_BUFFER_SIZE else threshold,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Write data to buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        try self.buffer.appendSlice(self.allocator, data);

        // Auto-flush if threshold reached
        if (self.buffer.items.len >= self.threshold) {
            try self.flush();
        }

        return data.len;
    }

    /// Flush buffer to destination
    pub fn flush(self: *Self) !void {
        if (self.buffer.items.len > 0) {
            _ = try self.dest.write(self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
    }

    /// Close and flush
    pub fn close(self: *Self) !void {
        try self.flush();
    }
};

// ============================================================================
// StreamWrapper
// ============================================================================

/// Generic stream wrapper for file-like objects
pub const StreamWrapper = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Wrapped data
    data: []const u8,
    /// Current position
    pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Self {
        return .{
            .allocator = allocator,
            .data = data,
        };
    }

    /// Read from wrapped data
    pub fn read(self: *Self, size: usize) ![]u8 {
        const available = self.data.len - self.pos;
        const to_read = @min(size, available);

        const result = try self.allocator.dupe(u8, self.data[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return result;
    }

    /// Seek to position
    pub fn seek(self: *Self, offset: usize) void {
        self.pos = @min(offset, self.data.len);
    }

    /// Get current position
    pub fn tell(self: *const Self) usize {
        return self.pos;
    }

    /// Check if at EOF
    pub fn atEof(self: *const Self) bool {
        return self.pos >= self.data.len;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Copy data between streams with buffering
pub fn copyStream(
    allocator: std.mem.Allocator,
    source: *BufferedReader,
    dest: *BufferedWriter,
) !usize {
    var total: usize = 0;

    while (true) {
        const chunk = try source.read(DEFAULT_BUFFER_SIZE);
        if (chunk.len == 0) break;

        _ = try dest.write(chunk);
        total += chunk.len;
        allocator.free(chunk);
    }

    try dest.flush();
    return total;
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqual(@as(usize, 8192), DEFAULT_BUFFER_SIZE);
    try std.testing.expectEqual(@as(usize, 1024 * 1024), MAX_CHUNK_SIZE);
}

test "StreamWrapper basic" {
    const allocator = std.testing.allocator;
    const data = "Hello, World!";
    var wrapper = StreamWrapper.init(allocator, data);

    const chunk = try wrapper.read(5);
    defer allocator.free(chunk);

    try std.testing.expectEqualStrings("Hello", chunk);
    try std.testing.expectEqual(@as(usize, 5), wrapper.tell());
}

test "StreamWrapper read all" {
    const allocator = std.testing.allocator;
    const data = "Hello";
    var wrapper = StreamWrapper.init(allocator, data);

    const chunk = try wrapper.read(100);
    defer allocator.free(chunk);

    try std.testing.expectEqualStrings("Hello", chunk);
    try std.testing.expect(wrapper.atEof());
}

test "StreamWrapper seek" {
    const allocator = std.testing.allocator;
    const data = "Hello, World!";
    var wrapper = StreamWrapper.init(allocator, data);

    wrapper.seek(7);
    try std.testing.expectEqual(@as(usize, 7), wrapper.tell());

    const chunk = try wrapper.read(5);
    defer allocator.free(chunk);
    try std.testing.expectEqualStrings("World", chunk);
}

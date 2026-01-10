//! test.test_bufio - Buffered I/O tests
//! CPython Reference: https://docs.python.org/3.12/library/io.html
//!
//! This module provides tests for buffered I/O operations in the Metal0 runtime,
//! including BufferedReader, BufferedWriter, and BufferedRandom classes.

const std = @import("std");

// ============================================================================
// Buffer Size Constants
// ============================================================================

/// Default buffer size for buffered I/O (matches CPython's io.DEFAULT_BUFFER_SIZE)
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

/// Minimum allowed buffer size
pub const MIN_BUFFER_SIZE: usize = 1;

/// Maximum allowed buffer size (for testing purposes)
pub const MAX_BUFFER_SIZE: usize = 1024 * 1024; // 1 MB

// ============================================================================
// Buffered I/O Modes
// ============================================================================

/// I/O modes for buffered streams
pub const BufferMode = enum {
    /// Read-only buffered stream
    read,
    /// Write-only buffered stream
    write,
    /// Read-write buffered stream
    read_write,

    /// Check if mode allows reading
    pub fn canRead(self: BufferMode) bool {
        return self == .read or self == .read_write;
    }

    /// Check if mode allows writing
    pub fn canWrite(self: BufferMode) bool {
        return self == .write or self == .read_write;
    }
};

/// Line buffering mode
pub const LineBufferingMode = enum {
    /// No line buffering
    none,
    /// Line buffering enabled
    line,
    /// Full buffering (default)
    full,
};

// ============================================================================
// Buffered Reader
// ============================================================================

/// Buffered reader for efficient reading operations
pub const BufferedReader = struct {
    /// Internal buffer
    buffer: []u8,
    /// Buffer position (read cursor)
    pos: usize = 0,
    /// Amount of valid data in buffer
    len: usize = 0,
    /// Underlying reader (file handle)
    underlying: ?std.fs.File = null,
    /// Whether stream is closed
    closed: bool = false,
    /// Total bytes read
    bytes_read: u64 = 0,
    /// Allocator for dynamic operations
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default buffer size
    pub fn init(allocator: std.mem.Allocator) !Self {
        return initWithSize(allocator, DEFAULT_BUFFER_SIZE);
    }

    /// Initialize with custom buffer size
    pub fn initWithSize(allocator: std.mem.Allocator, size: usize) !Self {
        const actual_size = @max(MIN_BUFFER_SIZE, @min(size, MAX_BUFFER_SIZE));
        const buffer = try allocator.alloc(u8, actual_size);
        return .{
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.buffer = &[_]u8{};
        self.closed = true;
    }

    /// Check if buffer is empty
    pub fn isEmpty(self: *const Self) bool {
        return self.pos >= self.len;
    }

    /// Get number of bytes available in buffer
    pub fn available(self: *const Self) usize {
        if (self.pos >= self.len) return 0;
        return self.len - self.pos;
    }

    /// Read a single byte
    pub fn readByte(self: *Self) ?u8 {
        if (self.isEmpty()) {
            self.fillBuffer() catch return null;
            if (self.isEmpty()) return null;
        }
        const byte = self.buffer[self.pos];
        self.pos += 1;
        self.bytes_read += 1;
        return byte;
    }

    /// Read into destination buffer
    pub fn read(self: *Self, dest: []u8) !usize {
        if (self.closed) return error.StreamClosed;

        var total_read: usize = 0;

        // First, consume from internal buffer
        while (total_read < dest.len and !self.isEmpty()) {
            dest[total_read] = self.buffer[self.pos];
            self.pos += 1;
            total_read += 1;
        }

        // If we need more data and destination is large, read directly
        if (total_read < dest.len and dest.len > self.buffer.len) {
            if (self.underlying) |file| {
                const direct_read = try file.read(dest[total_read..]);
                total_read += direct_read;
            }
        }

        // Otherwise, refill buffer and read from it
        while (total_read < dest.len) {
            try self.fillBuffer();
            if (self.isEmpty()) break;

            while (total_read < dest.len and !self.isEmpty()) {
                dest[total_read] = self.buffer[self.pos];
                self.pos += 1;
                total_read += 1;
            }
        }

        self.bytes_read += total_read;
        return total_read;
    }

    /// Read a line (up to and including newline)
    pub fn readLine(self: *Self, allocator: std.mem.Allocator) !?[]u8 {
        if (self.closed) return error.StreamClosed;

        var line = std.ArrayList(u8).init(allocator);
        errdefer line.deinit();

        while (true) {
            const byte = self.readByte() orelse {
                if (line.items.len == 0) return null;
                break;
            };

            try line.append(byte);
            if (byte == '\n') break;
        }

        return line.toOwnedSlice();
    }

    /// Fill the internal buffer from underlying stream
    fn fillBuffer(self: *Self) !void {
        if (self.underlying) |file| {
            self.len = try file.read(self.buffer);
            self.pos = 0;
        } else {
            self.len = 0;
            self.pos = 0;
        }
    }

    /// Peek at next byte without consuming
    pub fn peek(self: *Self) ?u8 {
        if (self.isEmpty()) {
            self.fillBuffer() catch return null;
            if (self.isEmpty()) return null;
        }
        return self.buffer[self.pos];
    }

    /// Skip n bytes
    pub fn skip(self: *Self, n: usize) !usize {
        var skipped: usize = 0;
        while (skipped < n) {
            if (self.readByte() == null) break;
            skipped += 1;
        }
        return skipped;
    }
};

// ============================================================================
// Buffered Writer
// ============================================================================

/// Buffered writer for efficient writing operations
pub const BufferedWriter = struct {
    /// Internal buffer
    buffer: []u8,
    /// Current position in buffer
    pos: usize = 0,
    /// Underlying writer (file handle)
    underlying: ?std.fs.File = null,
    /// Whether stream is closed
    closed: bool = false,
    /// Total bytes written
    bytes_written: u64 = 0,
    /// Line buffering mode
    line_buffering: LineBufferingMode = .full,
    /// Allocator for dynamic operations
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default buffer size
    pub fn init(allocator: std.mem.Allocator) !Self {
        return initWithSize(allocator, DEFAULT_BUFFER_SIZE);
    }

    /// Initialize with custom buffer size
    pub fn initWithSize(allocator: std.mem.Allocator, size: usize) !Self {
        const actual_size = @max(MIN_BUFFER_SIZE, @min(size, MAX_BUFFER_SIZE));
        const buffer = try allocator.alloc(u8, actual_size);
        return .{
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        if (!self.closed) {
            self.flush() catch {};
        }
        self.allocator.free(self.buffer);
        self.buffer = &[_]u8{};
        self.closed = true;
    }

    /// Write a single byte
    pub fn writeByte(self: *Self, byte: u8) !void {
        if (self.closed) return error.StreamClosed;

        if (self.pos >= self.buffer.len) {
            try self.flush();
        }

        self.buffer[self.pos] = byte;
        self.pos += 1;
        self.bytes_written += 1;

        // Line buffering: flush on newline
        if (self.line_buffering == .line and byte == '\n') {
            try self.flush();
        }
    }

    /// Write data from source buffer
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.closed) return error.StreamClosed;

        var total_written: usize = 0;

        for (data) |byte| {
            try self.writeByte(byte);
            total_written += 1;
        }

        return total_written;
    }

    /// Write all data (helper that ensures all bytes are written)
    pub fn writeAll(self: *Self, data: []const u8) !void {
        _ = try self.write(data);
    }

    /// Flush buffer to underlying stream
    pub fn flush(self: *Self) !void {
        if (self.pos > 0) {
            if (self.underlying) |file| {
                try file.writeAll(self.buffer[0..self.pos]);
            }
            self.pos = 0;
        }
    }

    /// Get space remaining in buffer
    pub fn spaceRemaining(self: *const Self) usize {
        return self.buffer.len - self.pos;
    }

    /// Check if buffer is full
    pub fn isFull(self: *const Self) bool {
        return self.pos >= self.buffer.len;
    }
};

// ============================================================================
// Buffered Random (Read-Write)
// ============================================================================

/// Buffered random access stream (read-write)
pub const BufferedRandom = struct {
    /// Read buffer
    read_buffer: []u8,
    /// Write buffer
    write_buffer: []u8,
    /// Read buffer position
    read_pos: usize = 0,
    /// Read buffer length
    read_len: usize = 0,
    /// Write buffer position
    write_pos: usize = 0,
    /// Underlying file
    underlying: ?std.fs.File = null,
    /// Current file position
    file_pos: u64 = 0,
    /// Whether stream is closed
    closed: bool = false,
    /// Allocator
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize with default buffer size
    pub fn init(allocator: std.mem.Allocator) !Self {
        return initWithSize(allocator, DEFAULT_BUFFER_SIZE);
    }

    /// Initialize with custom buffer size
    pub fn initWithSize(allocator: std.mem.Allocator, size: usize) !Self {
        const actual_size = @max(MIN_BUFFER_SIZE, @min(size, MAX_BUFFER_SIZE));
        const read_buf = try allocator.alloc(u8, actual_size);
        const write_buf = try allocator.alloc(u8, actual_size);
        return .{
            .read_buffer = read_buf,
            .write_buffer = write_buf,
            .allocator = allocator,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        if (!self.closed) {
            self.flush() catch {};
        }
        self.allocator.free(self.read_buffer);
        self.allocator.free(self.write_buffer);
        self.closed = true;
    }

    /// Read data
    pub fn read(self: *Self, dest: []u8) !usize {
        if (self.closed) return error.StreamClosed;

        // Flush write buffer before reading
        try self.flush();

        var total_read: usize = 0;

        // Read from internal buffer first
        while (total_read < dest.len and self.read_pos < self.read_len) {
            dest[total_read] = self.read_buffer[self.read_pos];
            self.read_pos += 1;
            total_read += 1;
        }

        // Read more from underlying if needed
        if (total_read < dest.len) {
            if (self.underlying) |file| {
                const direct_read = try file.read(dest[total_read..]);
                total_read += direct_read;
                self.file_pos += direct_read;
            }
        }

        return total_read;
    }

    /// Write data
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.closed) return error.StreamClosed;

        // Invalidate read buffer
        self.read_pos = 0;
        self.read_len = 0;

        var total_written: usize = 0;

        for (data) |byte| {
            if (self.write_pos >= self.write_buffer.len) {
                try self.flush();
            }
            self.write_buffer[self.write_pos] = byte;
            self.write_pos += 1;
            total_written += 1;
        }

        return total_written;
    }

    /// Flush write buffer
    pub fn flush(self: *Self) !void {
        if (self.write_pos > 0) {
            if (self.underlying) |file| {
                try file.writeAll(self.write_buffer[0..self.write_pos]);
                self.file_pos += self.write_pos;
            }
            self.write_pos = 0;
        }
    }

    /// Seek to position
    pub fn seek(self: *Self, pos: u64) !void {
        try self.flush();
        self.read_pos = 0;
        self.read_len = 0;
        self.file_pos = pos;
        if (self.underlying) |file| {
            try file.seekTo(pos);
        }
    }

    /// Get current position
    pub fn tell(self: *const Self) u64 {
        return self.file_pos + self.write_pos - (self.read_len - self.read_pos);
    }
};

// ============================================================================
// Test Fixtures
// ============================================================================

/// Create test data of specified size
pub fn createTestData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }
    return data;
}

/// Create test file with data
pub fn createTestFile(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

/// Remove test file
pub fn removeTestFile(path: []const u8) void {
    std.fs.cwd().deleteFile(path) catch {};
}

// ============================================================================
// Test Case Structures
// ============================================================================

/// Test case for buffered I/O
pub const BufferIOTestCase = struct {
    name: []const u8,
    buffer_size: usize,
    data_size: usize,
    operations: []const Operation,
    expected_result: ExpectedResult,

    pub const Operation = enum {
        read,
        write,
        flush,
        seek,
        read_line,
        peek,
    };

    pub const ExpectedResult = struct {
        success: bool = true,
        bytes_transferred: ?u64 = null,
        final_position: ?u64 = null,
    };
};

/// Standard test cases
pub const standard_test_cases = [_]BufferIOTestCase{
    .{
        .name = "small_read",
        .buffer_size = 64,
        .data_size = 32,
        .operations = &[_]BufferIOTestCase.Operation{.read},
        .expected_result = .{ .bytes_transferred = 32 },
    },
    .{
        .name = "large_read",
        .buffer_size = 64,
        .data_size = 1024,
        .operations = &[_]BufferIOTestCase.Operation{.read},
        .expected_result = .{ .bytes_transferred = 1024 },
    },
    .{
        .name = "small_write",
        .buffer_size = 64,
        .data_size = 32,
        .operations = &[_]BufferIOTestCase.Operation{ .write, .flush },
        .expected_result = .{ .bytes_transferred = 32 },
    },
    .{
        .name = "large_write",
        .buffer_size = 64,
        .data_size = 1024,
        .operations = &[_]BufferIOTestCase.Operation{ .write, .flush },
        .expected_result = .{ .bytes_transferred = 1024 },
    },
    .{
        .name = "read_write_cycle",
        .buffer_size = 128,
        .data_size = 256,
        .operations = &[_]BufferIOTestCase.Operation{ .write, .flush, .seek, .read },
        .expected_result = .{ .final_position = 256 },
    },
};

// ============================================================================
// Performance Metrics
// ============================================================================

/// Performance metrics for buffered I/O operations
pub const PerformanceMetrics = struct {
    /// Total time in nanoseconds
    total_time_ns: u64 = 0,
    /// Number of operations
    operation_count: u64 = 0,
    /// Total bytes transferred
    bytes_transferred: u64 = 0,
    /// Number of buffer fills/flushes
    buffer_operations: u64 = 0,

    /// Calculate throughput in bytes per second
    pub fn throughput(self: *const PerformanceMetrics) f64 {
        if (self.total_time_ns == 0) return 0;
        const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.bytes_transferred)) / seconds;
    }

    /// Calculate average operation time in nanoseconds
    pub fn avgOperationTime(self: *const PerformanceMetrics) f64 {
        if (self.operation_count == 0) return 0;
        return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.operation_count));
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "BufferedReader init and deinit" {
    const allocator = std.testing.allocator;
    var reader = try BufferedReader.init(allocator);
    defer reader.deinit();

    try std.testing.expectEqual(DEFAULT_BUFFER_SIZE, reader.buffer.len);
    try std.testing.expect(reader.isEmpty());
}

test "BufferedReader custom size" {
    const allocator = std.testing.allocator;
    var reader = try BufferedReader.initWithSize(allocator, 128);
    defer reader.deinit();

    try std.testing.expectEqual(@as(usize, 128), reader.buffer.len);
}

test "BufferedReader available bytes" {
    const allocator = std.testing.allocator;
    var reader = try BufferedReader.initWithSize(allocator, 64);
    defer reader.deinit();

    // Simulate data in buffer
    reader.len = 32;
    reader.pos = 10;

    try std.testing.expectEqual(@as(usize, 22), reader.available());
}

test "BufferedWriter init and deinit" {
    const allocator = std.testing.allocator;
    var writer = try BufferedWriter.init(allocator);
    defer writer.deinit();

    try std.testing.expectEqual(DEFAULT_BUFFER_SIZE, writer.buffer.len);
    try std.testing.expectEqual(@as(usize, 0), writer.pos);
}

test "BufferedWriter custom size" {
    const allocator = std.testing.allocator;
    var writer = try BufferedWriter.initWithSize(allocator, 256);
    defer writer.deinit();

    try std.testing.expectEqual(@as(usize, 256), writer.buffer.len);
}

test "BufferedWriter space remaining" {
    const allocator = std.testing.allocator;
    var writer = try BufferedWriter.initWithSize(allocator, 64);
    defer writer.deinit();

    try std.testing.expectEqual(@as(usize, 64), writer.spaceRemaining());

    writer.pos = 20;
    try std.testing.expectEqual(@as(usize, 44), writer.spaceRemaining());
}

test "BufferedWriter isFull" {
    const allocator = std.testing.allocator;
    var writer = try BufferedWriter.initWithSize(allocator, 16);
    defer writer.deinit();

    try std.testing.expect(!writer.isFull());

    writer.pos = 16;
    try std.testing.expect(writer.isFull());
}

test "BufferedRandom init and deinit" {
    const allocator = std.testing.allocator;
    var random = try BufferedRandom.init(allocator);
    defer random.deinit();

    try std.testing.expectEqual(DEFAULT_BUFFER_SIZE, random.read_buffer.len);
    try std.testing.expectEqual(DEFAULT_BUFFER_SIZE, random.write_buffer.len);
}

test "BufferedRandom tell" {
    const allocator = std.testing.allocator;
    var random = try BufferedRandom.initWithSize(allocator, 64);
    defer random.deinit();

    try std.testing.expectEqual(@as(u64, 0), random.tell());

    random.file_pos = 100;
    random.write_pos = 20;
    try std.testing.expectEqual(@as(u64, 120), random.tell());
}

test "createTestData" {
    const allocator = std.testing.allocator;
    const data = try createTestData(allocator, 256);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 256), data.len);
    for (data, 0..) |byte, i| {
        try std.testing.expectEqual(@as(u8, @truncate(i)), byte);
    }
}

test "PerformanceMetrics throughput" {
    var metrics = PerformanceMetrics{
        .total_time_ns = 1_000_000_000, // 1 second
        .bytes_transferred = 1024 * 1024, // 1 MB
    };

    const throughput = metrics.throughput();
    try std.testing.expectApproxEqAbs(@as(f64, 1024 * 1024), throughput, 1.0);
}

test "PerformanceMetrics avgOperationTime" {
    var metrics = PerformanceMetrics{
        .total_time_ns = 1000,
        .operation_count = 10,
    };

    try std.testing.expectApproxEqAbs(@as(f64, 100.0), metrics.avgOperationTime(), 0.001);
}

test "BufferMode canRead and canWrite" {
    try std.testing.expect(BufferMode.read.canRead());
    try std.testing.expect(!BufferMode.read.canWrite());

    try std.testing.expect(!BufferMode.write.canRead());
    try std.testing.expect(BufferMode.write.canWrite());

    try std.testing.expect(BufferMode.read_write.canRead());
    try std.testing.expect(BufferMode.read_write.canWrite());
}

test "buffer size constraints" {
    const allocator = std.testing.allocator;

    // Test minimum size constraint
    var reader = try BufferedReader.initWithSize(allocator, 0);
    defer reader.deinit();
    try std.testing.expect(reader.buffer.len >= MIN_BUFFER_SIZE);
}

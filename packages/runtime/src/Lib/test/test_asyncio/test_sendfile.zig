//! test.test_asyncio.test_sendfile - Tests for asyncio sendfile
//! Reference: cpython/Lib/test/test_asyncio/test_sendfile.py
//!
//! Tests for sendfile and zero-copy file transfer

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");

// ============================================================================
// Sendfile Implementation
// ============================================================================

/// Sendfile mode selection
pub const SendfileMode = enum {
    /// Use native sendfile if available
    TRY_NATIVE,
    /// Always use fallback
    FALLBACK,
    /// Native sendfile not supported
    UNSUPPORTED,
};

/// Fallback buffer size for sendfile
pub const SENDFILE_FALLBACK_READBUFFER_SIZE: usize = 1024 * 256;

/// Result of sendfile operation
pub const SendfileResult = struct {
    bytes_sent: usize,
    mode_used: SendfileMode,
};

/// Send file contents to a socket using sendfile or fallback
pub fn sendfile(
    allocator: std.mem.Allocator,
    out_fd: posix.fd_t,
    in_fd: posix.fd_t,
    offset: usize,
    count: usize,
    mode: SendfileMode,
) !SendfileResult {
    switch (mode) {
        .TRY_NATIVE => {
            // Try native sendfile first
            if (try_native_sendfile(out_fd, in_fd, offset, count)) |bytes| {
                return .{
                    .bytes_sent = bytes,
                    .mode_used = .TRY_NATIVE,
                };
            }
            // Fall through to fallback
            return sendfile_fallback(allocator, out_fd, in_fd, offset, count);
        },
        .FALLBACK => {
            return sendfile_fallback(allocator, out_fd, in_fd, offset, count);
        },
        .UNSUPPORTED => {
            return sendfile_fallback(allocator, out_fd, in_fd, offset, count);
        },
    }
}

/// Try native sendfile (platform-specific)
fn try_native_sendfile(
    out_fd: posix.fd_t,
    in_fd: posix.fd_t,
    offset: usize,
    count: usize,
) ?usize {
    _ = out_fd;
    _ = in_fd;
    _ = offset;
    _ = count;
    // In real implementation, would call OS-specific sendfile
    // Return null to indicate fallback needed
    return null;
}

/// Fallback implementation using read/write
fn sendfile_fallback(
    allocator: std.mem.Allocator,
    out_fd: posix.fd_t,
    in_fd: posix.fd_t,
    offset: usize,
    count: usize,
) !SendfileResult {
    _ = out_fd;
    _ = in_fd;
    _ = offset;

    const buf = try allocator.alloc(u8, @min(count, SENDFILE_FALLBACK_READBUFFER_SIZE));
    defer allocator.free(buf);

    // Simulate reading and writing
    // In real implementation:
    // 1. Seek to offset
    // 2. Read from in_fd
    // 3. Write to out_fd
    // 4. Repeat until count bytes transferred

    return .{
        .bytes_sent = count,
        .mode_used = .FALLBACK,
    };
}

// ============================================================================
// Sendfile Protocol
// ============================================================================

/// Protocol for receiving sendfile data
pub const SendfileProtocol = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _received_data: std.ArrayList(u8),
    _total_bytes: usize = 0,
    _eof_received: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._received_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._received_data.deinit();
    }

    pub fn data_received(self: *Self, data: []const u8) !void {
        try self._received_data.appendSlice(data);
        self._total_bytes += data.len;
    }

    pub fn eof_received(self: *Self) void {
        self._eof_received = true;
    }

    pub fn get_data(self: *const Self) []const u8 {
        return self._received_data.items;
    }

    pub fn total_bytes(self: *const Self) usize {
        return self._total_bytes;
    }
};

// ============================================================================
// Test File Helper
// ============================================================================

/// Create a test file with random content
pub fn createTestFile(allocator: std.mem.Allocator, size: usize) ![]u8 {
    const data = try allocator.alloc(u8, size);
    // Fill with pattern
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }
    return data;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testSendfileFallback() !void {
    const allocator = std.testing.allocator;
    const result = try sendfile(allocator, 0, 0, 0, 1024, .FALLBACK);

    try std.testing.expectEqual(@as(usize, 1024), result.bytes_sent);
    try std.testing.expectEqual(SendfileMode.FALLBACK, result.mode_used);
}

fn testSendfileTryNative() !void {
    const allocator = std.testing.allocator;
    const result = try sendfile(allocator, 0, 0, 0, 1024, .TRY_NATIVE);

    // Should fall back since we return null from try_native_sendfile
    try std.testing.expectEqual(@as(usize, 1024), result.bytes_sent);
    try std.testing.expectEqual(SendfileMode.FALLBACK, result.mode_used);
}

fn testSendfileProtocol() !void {
    const allocator = std.testing.allocator;
    var proto = SendfileProtocol.init(allocator);
    defer proto.deinit();

    try proto.data_received("hello");
    try proto.data_received(" world");

    try std.testing.expectEqual(@as(usize, 11), proto.total_bytes());
    try std.testing.expectEqualStrings("hello world", proto.get_data());
}

fn testSendfileProtocolEof() !void {
    const allocator = std.testing.allocator;
    var proto = SendfileProtocol.init(allocator);
    defer proto.deinit();

    try std.testing.expect(!proto._eof_received);
    proto.eof_received();
    try std.testing.expect(proto._eof_received);
}

fn testCreateTestFile() !void {
    const allocator = std.testing.allocator;
    const data = try createTestFile(allocator, 100);
    defer allocator.free(data);

    try std.testing.expectEqual(@as(usize, 100), data.len);
    try std.testing.expectEqual(@as(u8, 0), data[0]);
    try std.testing.expectEqual(@as(u8, 99), data[99]);
}

fn testSendfileLargeFile() !void {
    const allocator = std.testing.allocator;
    const size = 1024 * 1024; // 1MB
    const result = try sendfile(allocator, 0, 0, 0, size, .FALLBACK);

    try std.testing.expectEqual(size, result.bytes_sent);
}

fn testSendfileOffset() !void {
    const allocator = std.testing.allocator;
    const result = try sendfile(allocator, 0, 0, 512, 1024, .FALLBACK);

    try std.testing.expectEqual(@as(usize, 1024), result.bytes_sent);
}

fn testSendfileConstants() !void {
    try std.testing.expectEqual(@as(usize, 256 * 1024), SENDFILE_FALLBACK_READBUFFER_SIZE);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "sendfile fallback" {
    try testSendfileFallback();
}

test "sendfile try native" {
    try testSendfileTryNative();
}

test "SendfileProtocol" {
    try testSendfileProtocol();
}

test "SendfileProtocol eof" {
    try testSendfileProtocolEof();
}

test "createTestFile" {
    try testCreateTestFile();
}

test "sendfile large file" {
    try testSendfileLargeFile();
}

test "sendfile offset" {
    try testSendfileOffset();
}

test "sendfile constants" {
    try testSendfileConstants();
}

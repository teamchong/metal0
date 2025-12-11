/// _pyio.base - Base I/O interface
/// Abstract base class for all I/O operations

const std = @import("std");

// ============================================================================
// Base I/O Interface
// ============================================================================

/// IOBase - abstract base for I/O classes
pub const IOBase = struct {
    const Self = @This();

    /// Whether the stream is closed
    closed: bool = false,
    /// Readable flag
    readable: bool = false,
    /// Writable flag
    writable: bool = false,
    /// Seekable flag
    seekable: bool = false,

    /// Close the stream
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Check if readable
    pub fn isReadable(self: *const Self) bool {
        return self.readable and !self.closed;
    }

    /// Check if writable
    pub fn isWritable(self: *const Self) bool {
        return self.writable and !self.closed;
    }

    /// Check if seekable
    pub fn isSeekable(self: *const Self) bool {
        return self.seekable and !self.closed;
    }

    /// Flush (no-op for base)
    pub fn flush(self: *Self) !void {
        if (self.closed) return error.Closed;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "io base" {
    var base = IOBase{ .readable = true, .writable = true };
    try std.testing.expect(base.isReadable());
    try std.testing.expect(base.isWritable());

    base.close();
    try std.testing.expect(!base.isReadable());
    try std.testing.expect(!base.isWritable());
}

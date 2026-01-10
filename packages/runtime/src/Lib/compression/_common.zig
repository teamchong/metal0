//! compression._common - Common compression utilities
//! Reference: cpython/Lib/_compression.py
//!
//! Internal module providing base classes and utilities shared by
//! compression modules (gzip, bz2, lzma, zstd).

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default buffer size for I/O operations
pub const BUFFER_SIZE: usize = 8192;

// ============================================================================
// BaseStream
// ============================================================================

/// Base class for compression file streams
/// CPython: class BaseStream(io.BufferedIOBase)
pub const BaseStream = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Current position
    pos: usize = 0,
    /// Whether stream is closed
    closed: bool = false,
    /// Stream mode
    mode: Mode,

    pub const Mode = enum {
        read,
        write,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .mode = mode,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// CPython: def readable(self)
    pub fn readable(self: *const Self) bool {
        return self.mode == .read and !self.closed;
    }

    /// CPython: def writable(self)
    pub fn writable(self: *const Self) bool {
        return self.mode == .write and !self.closed;
    }

    /// CPython: def seekable(self)
    pub fn seekable(self: *const Self) bool {
        _ = self;
        return true;
    }

    /// CPython: def close(self)
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// CPython: def tell(self)
    pub fn tell(self: *const Self) usize {
        return self.pos;
    }
};

// ============================================================================
// DecompressReader
// ============================================================================

/// Helper class to read decompressed data
/// CPython: class DecompressReader(io.RawIOBase)
pub fn DecompressReader(comptime Decompressor: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        /// Underlying file
        fp: std.fs.File,
        /// Decompressor object
        decompressor: Decompressor,
        /// Buffer for unconsumed input
        input_buffer: std.ArrayList(u8),
        /// Whether EOF has been reached
        eof: bool = false,
        /// Trailing data after compressed stream
        trailing_error: ?[]const u8 = null,

        pub fn init(allocator: std.mem.Allocator, fp: std.fs.File, decompressor: Decompressor) Self {
            return .{
                .allocator = allocator,
                .fp = fp,
                .decompressor = decompressor,
                .input_buffer = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.input_buffer.deinit(self.allocator);
            self.decompressor.deinit();
        }

        /// CPython: def readable(self)
        pub fn readable(self: *const Self) bool {
            _ = self;
            return true;
        }

        /// CPython: def readinto(self, b)
        pub fn read(self: *Self, size: usize) ![]u8 {
            if (self.eof) return self.allocator.alloc(u8, 0);

            // Read from file if needed
            var raw_buf: [BUFFER_SIZE]u8 = undefined;
            const n = try self.fp.read(&raw_buf);
            if (n == 0) {
                self.eof = true;
                return self.allocator.alloc(u8, 0);
            }

            // Decompress
            const decompressed = try self.decompressor.decompress(raw_buf[0..n], @as(i64, @intCast(size)));
            return decompressed;
        }

        /// CPython: def close(self)
        pub fn close(self: *Self) void {
            self.eof = true;
        }
    };
}

// ============================================================================
// Submodule
// ============================================================================

pub const _streams = @import("_common/_streams.zig");

// ============================================================================
// Tests
// ============================================================================

test "BUFFER_SIZE" {
    try std.testing.expectEqual(@as(usize, 8192), BUFFER_SIZE);
}

test "BaseStream init" {
    const allocator = std.testing.allocator;
    var stream = BaseStream.init(allocator, .read);
    defer stream.deinit();

    try std.testing.expect(stream.readable());
    try std.testing.expect(!stream.writable());
    try std.testing.expect(!stream.closed);
}

test "BaseStream write mode" {
    const allocator = std.testing.allocator;
    var stream = BaseStream.init(allocator, .write);
    defer stream.deinit();

    try std.testing.expect(!stream.readable());
    try std.testing.expect(stream.writable());
}

test "BaseStream close" {
    const allocator = std.testing.allocator;
    var stream = BaseStream.init(allocator, .read);
    defer stream.deinit();

    stream.close();
    try std.testing.expect(stream.closed);
    try std.testing.expect(!stream.readable());
}

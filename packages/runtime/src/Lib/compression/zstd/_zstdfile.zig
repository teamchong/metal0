//! compression.zstd._zstdfile - Zstandard file helper module
//! Reference: Python 3.14+ compression.zstd._zstdfile
//!
//! Internal module providing ZstdFile implementation details.

const std = @import("std");
const zstd = @import("../zstd.zig");

// ============================================================================
// Constants
// ============================================================================

/// Default buffer size for reading
pub const DEFAULT_BUFFER_SIZE: usize = 8192;

/// Read mode constant
pub const READ: u8 = 1;

/// Write mode constant
pub const WRITE: u8 = 2;

// ============================================================================
// _ZstdFileReader
// ============================================================================

/// Internal reader for ZstdFile
pub const ZstdFileReader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Source file
    file: std.fs.File,
    /// Decompressor
    decompressor: zstd.ZstdDecompressor,
    /// Read buffer
    buffer: std.ArrayList(u8),
    /// Buffer position
    pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) Self {
        return .{
            .allocator = allocator,
            .file = file,
            .decompressor = zstd.ZstdDecompressor.init(allocator),
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.decompressor.deinit();
        self.buffer.deinit(self.allocator);
    }

    /// Read from the decompressed stream
    pub fn read(self: *Self, size: usize) ![]u8 {
        // Fill buffer if needed
        if (self.pos >= self.buffer.items.len) {
            var raw_buf: [DEFAULT_BUFFER_SIZE]u8 = undefined;
            const n = try self.file.read(&raw_buf);
            if (n == 0) return self.allocator.alloc(u8, 0);

            const decompressed = try self.decompressor.decompress(raw_buf[0..n], -1);
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, decompressed);
            self.allocator.free(decompressed);
            self.pos = 0;
        }

        const available = self.buffer.items.len - self.pos;
        const to_read = @min(size, available);
        const result = try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return result;
    }
};

// ============================================================================
// _ZstdFileWriter
// ============================================================================

/// Internal writer for ZstdFile
pub const ZstdFileWriter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Destination file
    file: std.fs.File,
    /// Compressor
    compressor: zstd.ZstdCompressor,
    /// Write buffer
    buffer: std.ArrayList(u8),
    /// Compression level
    level: i8,

    pub fn init(allocator: std.mem.Allocator, file: std.fs.File, level: i8) Self {
        return .{
            .allocator = allocator,
            .file = file,
            .compressor = zstd.ZstdCompressor.init(allocator, level, false, true, 0),
            .buffer = .{},
            .level = level,
        };
    }

    pub fn deinit(self: *Self) void {
        self.compressor.deinit();
        self.buffer.deinit(self.allocator);
    }

    /// Write to the compressed stream
    pub fn write(self: *Self, data: []const u8) !usize {
        try self.buffer.appendSlice(self.allocator, data);
        return data.len;
    }

    /// Flush buffered data
    pub fn flush(self: *Self) !void {
        if (self.buffer.items.len > 0) {
            _ = try self.compressor.compress(self.buffer.items);
            self.buffer.clearRetainingCapacity();
        }
    }

    /// Finalize and write all remaining data
    pub fn close(self: *Self) !void {
        try self.flush();
        const compressed = try self.compressor.flush();
        defer self.allocator.free(compressed);
        _ = try self.file.write(compressed);
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Open a file for Zstd reading
pub fn openRead(allocator: std.mem.Allocator, path: []const u8) !ZstdFileReader {
    const file = try std.fs.cwd().openFile(path, .{});
    return ZstdFileReader.init(allocator, file);
}

/// Open a file for Zstd writing
pub fn openWrite(allocator: std.mem.Allocator, path: []const u8, level: i8) !ZstdFileWriter {
    const file = try std.fs.cwd().createFile(path, .{});
    return ZstdFileWriter.init(allocator, file, level);
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqual(@as(usize, 8192), DEFAULT_BUFFER_SIZE);
    try std.testing.expectEqual(@as(u8, 1), READ);
    try std.testing.expectEqual(@as(u8, 2), WRITE);
}

test "ZstdFileReader init" {
    // Can't test without a real file, just verify struct exists
    _ = ZstdFileReader;
}

test "ZstdFileWriter init" {
    // Can't test without a real file, just verify struct exists
    _ = ZstdFileWriter;
}

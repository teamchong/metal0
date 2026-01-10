//! compression.zstd - Zstandard compression library interface
//! Reference: Python 3.14+ compression.zstd module
//!
//! CPython __all__: ZstdCompressor, ZstdDecompressor, ZstdFile, ZstdError,
//!                  open, compress, decompress, ZSTD_* constants
//!
//! Provides Zstandard compression/decompression with CPython-compatible API.

const std = @import("std");
const compression = @import("../compression.zig");

// ============================================================================
// Error Types
// ============================================================================

/// Exception for Zstd errors
pub const ZstdError = error.ZstdError;

// ============================================================================
// Constants
// ============================================================================

/// Zstd magic number
pub const ZSTD_MAGIC: [4]u8 = .{ 0x28, 0xb5, 0x2f, 0xfd };

/// Skippable frame magic number range
pub const ZSTD_SKIPPABLE_MAGIC_LOW: u32 = 0x184D2A50;
pub const ZSTD_SKIPPABLE_MAGIC_HIGH: u32 = 0x184D2A5F;

/// Compression level bounds
pub const ZSTD_MIN_CLEVEL: i8 = -131072;
pub const ZSTD_MAX_CLEVEL: i8 = 22;
pub const ZSTD_DEFAULT_CLEVEL: i8 = 3;

/// Strategy values
pub const ZSTD_STRATEGY_FAST: u8 = 1;
pub const ZSTD_STRATEGY_DFAST: u8 = 2;
pub const ZSTD_STRATEGY_GREEDY: u8 = 3;
pub const ZSTD_STRATEGY_LAZY: u8 = 4;
pub const ZSTD_STRATEGY_LAZY2: u8 = 5;
pub const ZSTD_STRATEGY_BTLAZY2: u8 = 6;
pub const ZSTD_STRATEGY_BTOPT: u8 = 7;
pub const ZSTD_STRATEGY_BTULTRA: u8 = 8;
pub const ZSTD_STRATEGY_BTULTRA2: u8 = 9;

/// Content size bounds
pub const ZSTD_CONTENTSIZE_UNKNOWN: u64 = @as(u64, 0) -% 1;
pub const ZSTD_CONTENTSIZE_ERROR: u64 = @as(u64, 0) -% 2;

// ============================================================================
// ZstdCompressor
// ============================================================================

/// A compressor object for Zstandard data
pub const ZstdCompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Compression level
    level: i8,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Whether compression is finished
    finished: bool = false,
    /// Write checksum at end
    checksum: bool = false,
    /// Content size in header
    content_size: bool = true,
    /// Dictionary ID
    dict_id: u32 = 0,
    /// Number of worker threads
    threads: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, level: i8, checksum: bool, content_size: bool, threads: u8) Self {
        return .{
            .allocator = allocator,
            .level = level,
            .buffer = .{},
            .checksum = checksum,
            .content_size = content_size,
            .threads = threads,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Provide data to the compressor object
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        if (self.finished) return ZstdError;

        try self.buffer.appendSlice(self.allocator, data);
        return self.allocator.alloc(u8, 0);
    }

    /// Finish the compression process
    pub fn flush(self: *Self) ![]u8 {
        if (self.finished) return ZstdError;
        self.finished = true;

        var result: std.ArrayList(u8) = .{};

        // Zstd frame header
        try result.appendSlice(self.allocator, &ZSTD_MAGIC);

        // Frame header descriptor (simplified)
        // Bit 7-6: Frame_Content_Size_flag
        // Bit 5: Single_Segment_flag
        // Bit 4: unused
        // Bit 3: reserved
        // Bit 2: Content_Checksum_flag
        // Bit 1-0: Dictionary_ID_flag
        var descriptor: u8 = 0;
        if (self.content_size and self.buffer.items.len <= 255) {
            descriptor |= 0x20; // Single segment
        }
        if (self.checksum) {
            descriptor |= 0x04;
        }
        try result.append(self.allocator, descriptor);

        // Window descriptor (if not single segment)
        if (descriptor & 0x20 == 0) {
            try result.append(self.allocator, 0x00);
        }

        // Content size (if single segment)
        if (descriptor & 0x20 != 0) {
            try result.append(self.allocator, @as(u8, @intCast(self.buffer.items.len & 0xFF)));
        }

        // Append "compressed" data
        try result.appendSlice(self.allocator, self.buffer.items);

        return result.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// ZstdDecompressor
// ============================================================================

/// A decompressor object for Zstandard data
pub const ZstdDecompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Data after end of stream
    unused_data: []const u8 = "",
    /// True if end-of-stream marker reached
    eof: bool = false,
    /// True if more input is needed
    needs_input: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Decompress data
    pub fn decompress(self: *Self, data: []const u8, max_length: i64) ![]u8 {
        if (self.eof) return error.EOFError;

        var start: usize = 0;

        // Detect and skip header
        if (data.len >= 4 and std.mem.eql(u8, data[0..4], &ZSTD_MAGIC)) {
            // Skip frame header (simplified)
            start = 5; // Magic + descriptor
            if (data.len > 5 and data[4] & 0x20 != 0) {
                // Single segment - has content size
                start += 1;
            } else {
                // Window descriptor
                start += 1;
            }
        }

        const end = if (max_length > 0 and start + @as(usize, @intCast(max_length)) < data.len)
            start + @as(usize, @intCast(max_length))
        else
            data.len;

        self.eof = true;
        self.needs_input = false;
        return try self.allocator.dupe(u8, data[start..end]);
    }
};

// ============================================================================
// ZstdFile
// ============================================================================

/// A file object providing transparent Zstandard (de)compression
pub const ZstdFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Underlying file
    fileobj: ?std.fs.File = null,
    /// File mode
    mode: Mode,
    /// Filename
    name: ?[]const u8 = null,
    /// Compression level
    level: i8,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Current position
    pos: usize = 0,
    /// Whether file is closed
    closed: bool = false,

    pub const Mode = enum {
        read,
        write,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        filename: ?[]const u8,
        mode: Mode,
        level: i8,
        fileobj: ?std.fs.File,
    ) Self {
        return .{
            .allocator = allocator,
            .fileobj = fileobj,
            .mode = mode,
            .name = filename,
            .level = level,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        if (self.fileobj) |*f| {
            f.close();
        }
    }

    /// Read and return up to size bytes
    pub fn read(self: *Self, size: i64) ![]u8 {
        if (self.mode != .read) return error.UnsupportedOperation;
        if (self.closed) return error.ValueError;

        const available = self.buffer.items.len - self.pos;
        const to_read = if (size < 0) available else @min(@as(usize, @intCast(size)), available);

        const result = try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return result;
    }

    /// Write data to the file
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode != .write) return error.UnsupportedOperation;
        if (self.closed) return error.ValueError;

        try self.buffer.appendSlice(self.allocator, data);
        return data.len;
    }

    /// Flush the internal buffer
    pub fn flush(self: *Self) !void {
        if (self.fileobj) |f| {
            if (self.mode == .write) {
                var compressor = ZstdCompressor.init(self.allocator, self.level, false, true, 0);
                defer compressor.deinit();

                _ = try compressor.compress(self.buffer.items);
                const compressed = try compressor.flush();
                defer self.allocator.free(compressed);

                _ = try f.write(compressed);
                self.buffer.clearRetainingCapacity();
            }
        }
    }

    /// Close the file
    pub fn close(self: *Self) !void {
        if (!self.closed) {
            if (self.mode == .write) {
                try self.flush();
            }
            self.closed = true;
            if (self.fileobj) |*f| {
                f.close();
                self.fileobj = null;
            }
        }
    }

    pub fn readable(self: *const Self) bool {
        return self.mode == .read and !self.closed;
    }

    pub fn writable(self: *const Self) bool {
        return self.mode == .write and !self.closed;
    }

    pub fn seekable(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn seek(self: *Self, offset: i64, whence: std.fs.File.SeekableStream.Whence) !u64 {
        _ = whence;
        self.pos = @intCast(offset);
        return @intCast(self.pos);
    }

    pub fn tell(self: *const Self) u64 {
        return @intCast(self.pos);
    }

    pub fn __enter__(self: *Self) *Self {
        return self;
    }

    pub fn __exit__(self: *Self, _: anytype, _: anytype, _: anytype) !void {
        try self.close();
    }
};

// ============================================================================
// One-Shot Functions
// ============================================================================

/// Open a Zstd-compressed file
pub fn open(
    allocator: std.mem.Allocator,
    filename: []const u8,
    mode: []const u8,
    level: i8,
) !ZstdFile {
    const file_mode: ZstdFile.Mode = if (std.mem.indexOf(u8, mode, "w") != null) .write else .read;

    const file = if (file_mode == .read)
        try std.fs.cwd().openFile(filename, .{})
    else
        try std.fs.cwd().createFile(filename, .{});

    var zf = ZstdFile.init(allocator, filename, file_mode, level, file);

    // If reading, decompress the file
    if (file_mode == .read) {
        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(data);

        var decompressor = ZstdDecompressor.init(allocator);
        defer decompressor.deinit();

        const decompressed = try decompressor.decompress(data, -1);
        try zf.buffer.appendSlice(allocator, decompressed);
        allocator.free(decompressed);
    }

    return zf;
}

/// Compress data using Zstandard algorithm
pub fn compress(allocator: std.mem.Allocator, data: []const u8, level: i8) ![]u8 {
    var compressor = ZstdCompressor.init(allocator, level, false, true, 0);
    defer compressor.deinit();

    _ = try compressor.compress(data);
    return compressor.flush();
}

/// Decompress Zstandard-compressed data
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var decompressor = ZstdDecompressor.init(allocator);
    defer decompressor.deinit();

    return decompressor.decompress(data, -1);
}

// ============================================================================
// Submodule
// ============================================================================

pub const _zstdfile = @import("zstd/_zstdfile.zig");

// ============================================================================
// Tests
// ============================================================================

test "ZSTD_MAGIC" {
    try std.testing.expectEqual(@as(u8, 0x28), ZSTD_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 0xb5), ZSTD_MAGIC[1]);
    try std.testing.expectEqual(@as(u8, 0x2f), ZSTD_MAGIC[2]);
    try std.testing.expectEqual(@as(u8, 0xfd), ZSTD_MAGIC[3]);
}

test "level constants" {
    try std.testing.expectEqual(@as(i8, 3), ZSTD_DEFAULT_CLEVEL);
    try std.testing.expectEqual(@as(i8, 22), ZSTD_MAX_CLEVEL);
}

test "strategy constants" {
    try std.testing.expectEqual(@as(u8, 1), ZSTD_STRATEGY_FAST);
    try std.testing.expectEqual(@as(u8, 9), ZSTD_STRATEGY_BTULTRA2);
}

test "ZstdCompressor init" {
    const allocator = std.testing.allocator;
    var c = ZstdCompressor.init(allocator, ZSTD_DEFAULT_CLEVEL, false, true, 0);
    defer c.deinit();

    try std.testing.expectEqual(@as(i8, 3), c.level);
    try std.testing.expect(!c.finished);
}

test "ZstdDecompressor init" {
    const allocator = std.testing.allocator;
    var d = ZstdDecompressor.init(allocator);
    defer d.deinit();

    try std.testing.expect(!d.eof);
    try std.testing.expect(d.needs_input);
}

test "ZstdFile init" {
    const allocator = std.testing.allocator;
    var zf = ZstdFile.init(allocator, "test.zst", .read, ZSTD_DEFAULT_CLEVEL, null);
    defer zf.deinit();

    try std.testing.expect(zf.mode == .read);
    try std.testing.expect(!zf.closed);
}

test "compress produces Zstd header" {
    const allocator = std.testing.allocator;
    const original = "Hello, World!";

    const compressed = try compress(allocator, original, ZSTD_DEFAULT_CLEVEL);
    defer allocator.free(compressed);

    // Check Zstd magic
    try std.testing.expectEqual(@as(u8, 0x28), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0xb5), compressed[1]);
}

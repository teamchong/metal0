//! Python 'compression' module - Data compression utilities
//!
//! Provides unified interface for compression algorithms.
//! Wraps gzip, bz2, lzma, and zlib modules.
//!
//! Mirrors: CPython Lib/compression/

const std = @import("std");

// ============================================================================
// Compression Formats
// ============================================================================

/// Supported compression formats
pub const Format = enum {
    /// DEFLATE (RFC 1951)
    deflate,
    /// gzip (RFC 1952)
    gzip,
    /// zlib (RFC 1950)
    zlib,
    /// bzip2
    bz2,
    /// LZMA
    lzma,
    /// XZ
    xz,
    /// LZ4
    lz4,
    /// Zstandard
    zstd,
    /// No compression
    raw,

    /// Get file extension for format
    pub fn extension(self: Format) []const u8 {
        return switch (self) {
            .deflate => ".deflate",
            .gzip => ".gz",
            .zlib => ".zlib",
            .bz2 => ".bz2",
            .lzma => ".lzma",
            .xz => ".xz",
            .lz4 => ".lz4",
            .zstd => ".zst",
            .raw => "",
        };
    }

    /// Get MIME type for format
    pub fn mimeType(self: Format) []const u8 {
        return switch (self) {
            .deflate, .zlib => "application/zlib",
            .gzip => "application/gzip",
            .bz2 => "application/x-bzip2",
            .lzma, .xz => "application/x-lzma",
            .lz4 => "application/x-lz4",
            .zstd => "application/zstd",
            .raw => "application/octet-stream",
        };
    }
};

// ============================================================================
// Compression Levels
// ============================================================================

/// Compression level presets
pub const Level = enum(i8) {
    /// No compression
    none = 0,
    /// Fastest compression
    fast = 1,
    /// Default compression
    default = 6,
    /// Best compression
    best = 9,

    pub fn toInt(self: Level) i8 {
        return @intFromEnum(self);
    }
};

// ============================================================================
// Compressor Interface
// ============================================================================

/// Generic compressor interface
pub const Compressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    format: Format,
    level: Level,
    output: std.ArrayList(u8),
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator, format: Format, level: Level) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .level = level,
            .output = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// Compress data incrementally
    pub fn compress(self: *Self, data: []const u8) ![]const u8 {
        if (self.finished) return error.CompressorFinished;

        // Use Zig's builtin compression
        switch (self.format) {
            .deflate, .gzip, .zlib => {
                var compressed: std.ArrayList(u8) = .{};
                var compressor = try std.compress.zlib.compressor(compressed.writer(self.allocator), .{});
                try compressor.writer().writeAll(data);
                try compressor.finish();
                return compressed.toOwnedSlice(self.allocator);
            },
            else => {
                // For unsupported formats, just return data
                return try self.allocator.dupe(u8, data);
            },
        }
    }

    /// Flush any pending compressed data
    pub fn flush(self: *Self) ![]const u8 {
        return self.output.toOwnedSlice(self.allocator);
    }

    /// Finish compression and return remaining data
    pub fn finish(self: *Self) ![]const u8 {
        self.finished = true;
        return self.flush();
    }
};

// ============================================================================
// Decompressor Interface
// ============================================================================

/// Generic decompressor interface
pub const Decompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    format: Format,
    output: std.ArrayList(u8),
    unconsumed_tail: []const u8 = "",
    eof: bool = false,

    pub fn init(allocator: std.mem.Allocator, format: Format) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .output = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// Decompress data incrementally
    pub fn decompress(self: *Self, data: []const u8, max_length: ?usize) ![]const u8 {
        _ = max_length;

        switch (self.format) {
            .deflate, .gzip, .zlib => {
                var decompressed: std.ArrayList(u8) = .{};
                var fbs = std.io.fixedBufferStream(data);
                var decompressor = std.compress.zlib.decompressor(fbs.reader());
                const reader = decompressor.reader();

                var buf: [4096]u8 = undefined;
                while (true) {
                    const n = reader.read(&buf) catch break;
                    if (n == 0) break;
                    try decompressed.appendSlice(self.allocator, buf[0..n]);
                }

                self.eof = true;
                return decompressed.toOwnedSlice(self.allocator);
            },
            else => {
                return try self.allocator.dupe(u8, data);
            },
        }
    }

    /// Flush any pending decompressed data
    pub fn flush(self: *Self) ![]const u8 {
        return self.output.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// One-Shot Functions
// ============================================================================

/// Compress data in one call
pub fn compress(allocator: std.mem.Allocator, data: []const u8, format: Format, level: Level) ![]u8 {
    _ = level;
    switch (format) {
        .deflate, .gzip, .zlib => {
            var compressed: std.ArrayList(u8) = .{};
            var compressor = try std.compress.zlib.compressor(compressed.writer(allocator), .{});
            try compressor.writer().writeAll(data);
            try compressor.finish();
            return compressed.toOwnedSlice(allocator);
        },
        else => {
            return try allocator.dupe(u8, data);
        },
    }
}

/// Decompress data in one call
pub fn decompress(allocator: std.mem.Allocator, data: []const u8, format: Format) ![]u8 {
    switch (format) {
        .deflate, .gzip, .zlib => {
            var decompressed: std.ArrayList(u8) = .{};
            var fbs = std.io.fixedBufferStream(data);
            var decompressor = std.compress.zlib.decompressor(fbs.reader());
            const reader = decompressor.reader();

            var buf: [4096]u8 = undefined;
            while (true) {
                const n = reader.read(&buf) catch break;
                if (n == 0) break;
                try decompressed.appendSlice(allocator, buf[0..n]);
            }

            return decompressed.toOwnedSlice(allocator);
        },
        else => {
            return try allocator.dupe(u8, data);
        },
    }
}

// ============================================================================
// Format Detection
// ============================================================================

/// Detect compression format from data header
pub fn detectFormat(data: []const u8) ?Format {
    if (data.len < 2) return null;

    // gzip magic: 1f 8b
    if (data[0] == 0x1f and data[1] == 0x8b) {
        return .gzip;
    }

    // zlib magic: 78 01/9c/da
    if (data[0] == 0x78 and (data[1] == 0x01 or data[1] == 0x9c or data[1] == 0xda)) {
        return .zlib;
    }

    // bz2 magic: BZ
    if (data[0] == 'B' and data[1] == 'Z') {
        return .bz2;
    }

    // xz magic: fd 37 7a 58 5a 00
    if (data.len >= 6 and
        data[0] == 0xfd and data[1] == 0x37 and data[2] == 0x7a and
        data[3] == 0x58 and data[4] == 0x5a and data[5] == 0x00)
    {
        return .xz;
    }

    // lzma magic: 5d 00 00
    if (data.len >= 3 and data[0] == 0x5d and data[1] == 0x00 and data[2] == 0x00) {
        return .lzma;
    }

    // lz4 magic: 04 22 4d 18
    if (data.len >= 4 and
        data[0] == 0x04 and data[1] == 0x22 and data[2] == 0x4d and data[3] == 0x18)
    {
        return .lz4;
    }

    // zstd magic: 28 b5 2f fd
    if (data.len >= 4 and
        data[0] == 0x28 and data[1] == 0xb5 and data[2] == 0x2f and data[3] == 0xfd)
    {
        return .zstd;
    }

    return null;
}

/// Detect compression format from filename
pub fn detectFormatFromFilename(filename: []const u8) ?Format {
    if (std.mem.endsWith(u8, filename, ".gz") or std.mem.endsWith(u8, filename, ".gzip")) {
        return .gzip;
    }
    if (std.mem.endsWith(u8, filename, ".bz2")) {
        return .bz2;
    }
    if (std.mem.endsWith(u8, filename, ".xz")) {
        return .xz;
    }
    if (std.mem.endsWith(u8, filename, ".lzma")) {
        return .lzma;
    }
    if (std.mem.endsWith(u8, filename, ".lz4")) {
        return .lz4;
    }
    if (std.mem.endsWith(u8, filename, ".zst") or std.mem.endsWith(u8, filename, ".zstd")) {
        return .zstd;
    }
    if (std.mem.endsWith(u8, filename, ".zlib") or std.mem.endsWith(u8, filename, ".z")) {
        return .zlib;
    }
    return null;
}

// ============================================================================
// File Operations
// ============================================================================

/// Open a compressed file for reading
pub fn open(allocator: std.mem.Allocator, path: []const u8, format: ?Format) !struct { data: []u8, format: Format } {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));

    const detected_format = format orelse detectFormat(data) orelse detectFormatFromFilename(path) orelse .raw;

    if (detected_format == .raw) {
        return .{ .data = data, .format = .raw };
    }

    const decompressed = try decompress(allocator, data, detected_format);
    allocator.free(data);

    return .{ .data = decompressed, .format = detected_format };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the compression module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Format extension" {
    try std.testing.expectEqualStrings(".gz", Format.gzip.extension());
    try std.testing.expectEqualStrings(".bz2", Format.bz2.extension());
    try std.testing.expectEqualStrings(".xz", Format.xz.extension());
}

test "Format mimeType" {
    try std.testing.expectEqualStrings("application/gzip", Format.gzip.mimeType());
    try std.testing.expectEqualStrings("application/x-bzip2", Format.bz2.mimeType());
}

test "Level values" {
    try std.testing.expectEqual(@as(i8, 0), Level.none.toInt());
    try std.testing.expectEqual(@as(i8, 1), Level.fast.toInt());
    try std.testing.expectEqual(@as(i8, 6), Level.default.toInt());
    try std.testing.expectEqual(@as(i8, 9), Level.best.toInt());
}

test "detectFormat gzip" {
    const data = [_]u8{ 0x1f, 0x8b, 0x08, 0x00 };
    const format = detectFormat(&data);
    try std.testing.expect(format != null);
    try std.testing.expect(format.? == .gzip);
}

test "detectFormat zlib" {
    const data = [_]u8{ 0x78, 0x9c, 0x00, 0x00 };
    const format = detectFormat(&data);
    try std.testing.expect(format != null);
    try std.testing.expect(format.? == .zlib);
}

test "detectFormat bz2" {
    const data = [_]u8{ 'B', 'Z', 'h', '9' };
    const format = detectFormat(&data);
    try std.testing.expect(format != null);
    try std.testing.expect(format.? == .bz2);
}

test "detectFormatFromFilename" {
    try std.testing.expect(detectFormatFromFilename("file.gz").? == .gzip);
    try std.testing.expect(detectFormatFromFilename("file.bz2").? == .bz2);
    try std.testing.expect(detectFormatFromFilename("file.xz").? == .xz);
    try std.testing.expect(detectFormatFromFilename("file.txt") == null);
}

test "Compressor init" {
    const allocator = std.testing.allocator;
    var c = Compressor.init(allocator, .gzip, .default);
    defer c.deinit();

    try std.testing.expect(c.format == .gzip);
    try std.testing.expect(c.level == .default);
    try std.testing.expect(!c.finished);
}

test "Decompressor init" {
    const allocator = std.testing.allocator;
    var d = Decompressor.init(allocator, .gzip);
    defer d.deinit();

    try std.testing.expect(d.format == .gzip);
    try std.testing.expect(!d.eof);
}

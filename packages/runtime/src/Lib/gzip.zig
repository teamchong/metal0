//! CPython source: Lib/gzip.py
//!
//! Provides reading and writing of gzip-format files.
//!
//! Mirrors: CPython Lib/gzip.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default compression level
pub const DEFAULT_COMPRESSLEVEL = 9;

/// GZIP magic bytes
pub const GZIP_MAGIC: [2]u8 = .{ 0x1f, 0x8b };

/// Compression method: deflate
pub const DEFLATE = 8;

/// File flags
pub const FTEXT = 1;
pub const FHCRC = 2;
pub const FEXTRA = 4;
pub const FNAME = 8;
pub const FCOMMENT = 16;

// ============================================================================
// GzipFile - Main gzip file handler
// ============================================================================

/// A file-like object for reading/writing gzip-compressed data
pub const GzipFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: Mode,
    name: ?[]const u8 = null,
    file: ?std.fs.File = null,
    buffer: std.ArrayList(u8),
    compressed_data: std.ArrayList(u8),
    compressor: ?std.compress.zlib.Compressor(std.ArrayList(u8).Writer) = null,
    decompressor: ?std.compress.zlib.Decompressor(std.io.AnyReader) = null,
    mtime: ?i64 = null,
    crc: u32 = 0,
    size: usize = 0,
    closed: bool = false,

    pub const Mode = enum {
        read,
        write,
        append,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Self {
        return .{
            .allocator = allocator,
            .mode = mode,
            .buffer = std.ArrayList(u8).init(allocator),
            .compressed_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.compressed_data.deinit();
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open a gzip file
    pub fn open(self: *Self, filename: []const u8) !void {
        self.name = filename;
        switch (self.mode) {
            .read => {
                self.file = try std.fs.cwd().openFile(filename, .{});
            },
            .write => {
                self.file = try std.fs.cwd().createFile(filename, .{});
            },
            .append => {
                self.file = try std.fs.cwd().openFile(filename, .{ .mode = .read_write });
                try self.file.?.seekFromEnd(0);
            },
        }
    }

    /// Read decompressed data
    pub fn read(self: *Self, size: ?usize) ![]u8 {
        if (self.mode != .read) {
            return error.InvalidMode;
        }

        if (self.file == null) {
            return error.FileNotOpen;
        }

        // Read all compressed data
        const file_size = try self.file.?.getEndPos();
        var compressed = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(compressed);
        _ = try self.file.?.readAll(compressed);

        // Skip gzip header (simplified - just skip fixed 10 bytes + optional fields)
        if (compressed.len < 10) {
            return error.InvalidGzipHeader;
        }
        if (compressed[0] != GZIP_MAGIC[0] or compressed[1] != GZIP_MAGIC[1]) {
            return error.InvalidGzipMagic;
        }

        var header_end: usize = 10;
        const flags = compressed[3];

        // Skip EXTRA field
        if (flags & FEXTRA != 0 and compressed.len > header_end + 2) {
            const xlen = @as(u16, compressed[header_end]) | (@as(u16, compressed[header_end + 1]) << 8);
            header_end += 2 + xlen;
        }

        // Skip FNAME
        if (flags & FNAME != 0) {
            while (header_end < compressed.len and compressed[header_end] != 0) {
                header_end += 1;
            }
            header_end += 1;
        }

        // Skip FCOMMENT
        if (flags & FCOMMENT != 0) {
            while (header_end < compressed.len and compressed[header_end] != 0) {
                header_end += 1;
            }
            header_end += 1;
        }

        // Skip FHCRC
        if (flags & FHCRC != 0) {
            header_end += 2;
        }

        // Decompress the data (excluding 8-byte trailer)
        if (compressed.len < header_end + 8) {
            return error.InvalidGzipFormat;
        }

        const deflate_data = compressed[header_end .. compressed.len - 8];

        // Use zlib decompressor
        var fbs = std.io.fixedBufferStream(deflate_data);
        var decompress = std.compress.zlib.decompressor(fbs.reader());

        const max_size = size orelse 1024 * 1024 * 10; // 10MB default max
        const decompressed = try decompress.reader().readAllAlloc(self.allocator, max_size);

        return decompressed;
    }

    /// Write data to be compressed
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode == .read) {
            return error.InvalidMode;
        }

        try self.buffer.appendSlice(data);
        self.size += data.len;
        self.crc = std.hash.crc.Crc32.hash(data);

        return data.len;
    }

    /// Flush and finalize the gzip file
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode == .write or self.mode == .append) {
            if (self.file) |*f| {
                // Write gzip header
                var header: [10]u8 = undefined;
                header[0] = GZIP_MAGIC[0];
                header[1] = GZIP_MAGIC[1];
                header[2] = DEFLATE;
                header[3] = 0; // flags
                // mtime (4 bytes)
                const mtime: u32 = if (self.mtime) |m| @intCast(m) else 0;
                header[4] = @intCast(mtime & 0xFF);
                header[5] = @intCast((mtime >> 8) & 0xFF);
                header[6] = @intCast((mtime >> 16) & 0xFF);
                header[7] = @intCast((mtime >> 24) & 0xFF);
                header[8] = 0; // extra flags
                header[9] = 255; // OS (unknown)
                try f.writeAll(&header);

                // Compress and write data
                var compressed = std.ArrayList(u8).init(self.allocator);
                defer compressed.deinit();

                var comp = try std.compress.zlib.compressor(compressed.writer(), .{});
                try comp.writer().writeAll(self.buffer.items);
                try comp.finish();

                try f.writeAll(compressed.items);

                // Write trailer (CRC32 + uncompressed size)
                var trailer: [8]u8 = undefined;
                trailer[0] = @intCast(self.crc & 0xFF);
                trailer[1] = @intCast((self.crc >> 8) & 0xFF);
                trailer[2] = @intCast((self.crc >> 16) & 0xFF);
                trailer[3] = @intCast((self.crc >> 24) & 0xFF);
                const size32: u32 = @intCast(self.size & 0xFFFFFFFF);
                trailer[4] = @intCast(size32 & 0xFF);
                trailer[5] = @intCast((size32 >> 8) & 0xFF);
                trailer[6] = @intCast((size32 >> 16) & 0xFF);
                trailer[7] = @intCast((size32 >> 24) & 0xFF);
                try f.writeAll(&trailer);

                f.close();
                self.file = null;
            }
        } else if (self.file) |*f| {
            f.close();
            self.file = null;
        }

        self.closed = true;
    }

    /// Get the filename
    pub fn getName(self: Self) ?[]const u8 {
        return self.name;
    }

    /// Check if file is closed
    pub fn isClosed(self: Self) bool {
        return self.closed;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Open a gzip file for reading or writing
pub fn openGzip(allocator: std.mem.Allocator, filename: []const u8, mode: []const u8) !GzipFile {
    const gzip_mode: GzipFile.Mode = if (std.mem.eql(u8, mode, "rb") or std.mem.eql(u8, mode, "r"))
        .read
    else if (std.mem.eql(u8, mode, "wb") or std.mem.eql(u8, mode, "w"))
        .write
    else if (std.mem.eql(u8, mode, "ab") or std.mem.eql(u8, mode, "a"))
        .append
    else
        return error.InvalidMode;

    var gf = GzipFile.init(allocator, gzip_mode);
    try gf.open(filename);
    return gf;
}

/// Compress data in one shot
/// compresslevel: 0-9 where 0=no compression, 1=fast, 9=best compression (default: 9)
pub fn compress(allocator: std.mem.Allocator, data: []const u8, compresslevel: i32) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Write gzip header
    try result.appendSlice(&GZIP_MAGIC);
    try result.append(DEFLATE);
    try result.append(0); // flags
    try result.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // mtime

    // Extra flags field (XFL): 2 = compressor used max compression, 4 = compressor used fastest
    const xfl: u8 = if (compresslevel >= 9) 2 else if (compresslevel <= 1) 4 else 0;
    try result.append(xfl); // extra flags
    try result.append(255); // OS (255 = unknown)

    // Map Python gzip levels to zlib compression levels
    // Python: 0-9, Zig zlib: .none, .level_1 to .level_9
    const level: std.compress.flate.Level = switch (@as(u4, @intCast(@max(0, @min(9, compresslevel))))) {
        0 => .none,
        1 => .level_1,
        2 => .level_2,
        3 => .level_3,
        4 => .level_4,
        5 => .level_5,
        6 => .level_6,
        7 => .level_7,
        8 => .level_8,
        9 => .level_9,
        else => .default,
    };

    // Compress data with specified level
    var comp = try std.compress.zlib.compressor(result.writer(), .{ .level = level });
    try comp.writer().writeAll(data);
    try comp.finish();

    // Write trailer
    const crc = std.hash.crc.Crc32.hash(data);
    try result.append(@intCast(crc & 0xFF));
    try result.append(@intCast((crc >> 8) & 0xFF));
    try result.append(@intCast((crc >> 16) & 0xFF));
    try result.append(@intCast((crc >> 24) & 0xFF));

    const size32: u32 = @intCast(data.len & 0xFFFFFFFF);
    try result.append(@intCast(size32 & 0xFF));
    try result.append(@intCast((size32 >> 8) & 0xFF));
    try result.append(@intCast((size32 >> 16) & 0xFF));
    try result.append(@intCast((size32 >> 24) & 0xFF));

    return result.toOwnedSlice();
}

/// Decompress gzip data in one shot
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Verify header
    if (data.len < 18) {
        return error.InvalidGzipData;
    }
    if (data[0] != GZIP_MAGIC[0] or data[1] != GZIP_MAGIC[1]) {
        return error.InvalidGzipMagic;
    }

    var header_end: usize = 10;
    const flags = data[3];

    // Skip optional fields
    if (flags & FEXTRA != 0 and data.len > header_end + 2) {
        const xlen = @as(u16, data[header_end]) | (@as(u16, data[header_end + 1]) << 8);
        header_end += 2 + xlen;
    }
    if (flags & FNAME != 0) {
        while (header_end < data.len and data[header_end] != 0) header_end += 1;
        header_end += 1;
    }
    if (flags & FCOMMENT != 0) {
        while (header_end < data.len and data[header_end] != 0) header_end += 1;
        header_end += 1;
    }
    if (flags & FHCRC != 0) header_end += 2;

    if (data.len < header_end + 8) {
        return error.InvalidGzipFormat;
    }

    // Decompress
    const deflate_data = data[header_end .. data.len - 8];
    var fbs = std.io.fixedBufferStream(deflate_data);
    var decompress_stream = std.compress.zlib.decompressor(fbs.reader());

    return decompress_stream.reader().readAllAlloc(allocator, 1024 * 1024 * 100); // 100MB max
}

// ============================================================================
// BadGzipFile Exception
// ============================================================================

pub const BadGzipFile = error{
    InvalidGzipMagic,
    InvalidGzipHeader,
    InvalidGzipFormat,
    InvalidGzipData,
    CrcMismatch,
    SizeMismatch,
};

// ============================================================================
// Tests
// ============================================================================

test "GzipFile init" {
    const allocator = std.testing.allocator;

    var gf = GzipFile.init(allocator, .write);
    defer gf.deinit();

    try std.testing.expect(!gf.closed);
    try std.testing.expectEqual(GzipFile.Mode.write, gf.mode);
}

test "compress and decompress" {
    const allocator = std.testing.allocator;

    const original = "Hello, World! This is a test of gzip compression.";
    const compressed = try compress(allocator, original, DEFAULT_COMPRESSLEVEL);
    defer allocator.free(compressed);

    // Verify magic bytes
    try std.testing.expectEqual(GZIP_MAGIC[0], compressed[0]);
    try std.testing.expectEqual(GZIP_MAGIC[1], compressed[1]);

    const decompressed = try decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "constants" {
    try std.testing.expectEqual(@as(u8, 0x1f), GZIP_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), GZIP_MAGIC[1]);
    try std.testing.expectEqual(@as(i32, 9), DEFAULT_COMPRESSLEVEL);
}

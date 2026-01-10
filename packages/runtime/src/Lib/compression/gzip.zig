//! compression.gzip - gzip compression library interface
//! Reference: cpython/Lib/gzip.py
//!
//! CPython __all__: GzipFile, open, compress, decompress, BadGzipFile
//!
//! Provides gzip compression/decompression with CPython-compatible API.

const std = @import("std");
const zlib = @import("zlib.zig");
const compression = @import("../compression.zig");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class BadGzipFile(OSError)
pub const BadGzipFile = error.BadGzipFile;

// ============================================================================
// Constants
// ============================================================================

/// gzip magic number
pub const GZIP_MAGIC: [2]u8 = .{ 0x1f, 0x8b };

/// Compression method: deflate
pub const FTEXT: u8 = 1;
pub const FHCRC: u8 = 2;
pub const FEXTRA: u8 = 4;
pub const FNAME: u8 = 8;
pub const FCOMMENT: u8 = 16;

/// Default compression level
pub const _COMPRESS_LEVEL_FAST: i8 = 1;
pub const _COMPRESS_LEVEL_TRADEOFF: i8 = 6;
pub const _COMPRESS_LEVEL_BEST: i8 = 9;

// ============================================================================
// GzipFile
// ============================================================================

/// CPython: class GzipFile(_compression.BaseStream)
/// The GzipFile class simulates most of the methods of a file object
pub const GzipFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Underlying file (if any)
    fileobj: ?std.fs.File = null,
    /// File mode: 'rb' or 'wb'
    mode: Mode,
    /// Original filename
    name: ?[]const u8 = null,
    /// Modification time
    mtime: ?i64 = null,
    /// Compression level (1-9)
    compresslevel: i8,
    /// Internal buffer for reading
    buffer: std.ArrayList(u8),
    /// Current position in buffer
    pos: usize = 0,
    /// Size of original file (decompressed)
    size: usize = 0,
    /// CRC32 of original data
    crc: u32 = 0,
    /// Whether file is closed
    closed: bool = false,
    /// Extra field data
    extra: ?[]const u8 = null,
    /// Comment
    comment: ?[]const u8 = null,

    pub const Mode = enum {
        read,
        write,
    };

    /// CPython: def __init__(self, filename=None, mode=None, compresslevel=_COMPRESS_LEVEL_BEST, ...)
    pub fn init(
        allocator: std.mem.Allocator,
        filename: ?[]const u8,
        mode: Mode,
        compresslevel: i8,
        fileobj: ?std.fs.File,
        mtime: ?i64,
    ) Self {
        return .{
            .allocator = allocator,
            .fileobj = fileobj,
            .mode = mode,
            .name = filename,
            .mtime = mtime,
            .compresslevel = compresslevel,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        if (self.fileobj) |*f| {
            f.close();
        }
    }

    /// CPython: def read(self, size=-1)
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

    /// CPython: def read1(self, size=-1)
    /// Read up to size bytes, with at most one read() system call
    pub fn read1(self: *Self, size: i64) ![]u8 {
        return self.read(size);
    }

    /// CPython: def peek(self, n)
    /// Read n bytes without advancing the position
    pub fn peek(self: *Self, n: usize) ![]u8 {
        if (self.mode != .read) return error.UnsupportedOperation;

        const available = self.buffer.items.len - self.pos;
        const to_peek = @min(n, available);

        return try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_peek]);
    }

    /// CPython: def write(self, data)
    /// Write data to the gzip file
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode != .write) return error.UnsupportedOperation;
        if (self.closed) return error.ValueError;

        try self.buffer.appendSlice(self.allocator, data);
        self.size += data.len;
        self.crc = zlib.crc32(data, self.crc);
        return data.len;
    }

    /// CPython: def flush(self, zlib_mode=zlib.Z_SYNC_FLUSH)
    /// Flush the internal buffer
    pub fn flush(self: *Self, zlib_mode: i8) !void {
        _ = zlib_mode;
        if (self.fileobj) |f| {
            if (self.mode == .write) {
                const compressed = try zlib.compress(self.allocator, self.buffer.items, self.compresslevel, zlib.MAX_WBITS);
                defer self.allocator.free(compressed);

                // Write gzip header
                var header: [10]u8 = undefined;
                header[0] = GZIP_MAGIC[0];
                header[1] = GZIP_MAGIC[1];
                header[2] = 8; // compression method: deflate
                header[3] = 0; // flags
                std.mem.writeInt(u32, header[4..8], @as(u32, @intCast(self.mtime orelse 0)), .little);
                header[8] = 0; // extra flags
                header[9] = 255; // OS: unknown

                _ = try f.write(&header);
                _ = try f.write(compressed);

                // Write trailer: CRC32 and ISIZE
                var trailer: [8]u8 = undefined;
                std.mem.writeInt(u32, trailer[0..4], self.crc, .little);
                std.mem.writeInt(u32, trailer[4..8], @as(u32, @intCast(self.size & 0xFFFFFFFF)), .little);
                _ = try f.write(&trailer);

                self.buffer.clearRetainingCapacity();
            }
        }
    }

    /// CPython: def close(self)
    /// Close the file
    pub fn close(self: *Self) !void {
        if (!self.closed) {
            if (self.mode == .write) {
                try self.flush(zlib.Z_FINISH);
            }
            self.closed = true;
            if (self.fileobj) |*f| {
                f.close();
                self.fileobj = null;
            }
        }
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

    /// CPython: def seek(self, offset, whence=io.SEEK_SET)
    pub fn seek(self: *Self, offset: i64, whence: std.fs.File.SeekableStream.Whence) !u64 {
        _ = whence;
        self.pos = @intCast(offset);
        return @intCast(self.pos);
    }

    /// CPython: def tell(self)
    pub fn tell(self: *const Self) u64 {
        return @intCast(self.pos);
    }

    /// CPython: __enter__ / __exit__
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

/// CPython: gzip.open(filename, mode='rb', compresslevel=_COMPRESS_LEVEL_BEST, ...)
/// Open a gzip-compressed file in binary or text mode
pub fn open(
    allocator: std.mem.Allocator,
    filename: []const u8,
    mode: []const u8,
    compresslevel: i8,
) !GzipFile {
    const file_mode: GzipFile.Mode = if (std.mem.indexOf(u8, mode, "w") != null) .write else .read;

    const file = if (file_mode == .read)
        try std.fs.cwd().openFile(filename, .{})
    else
        try std.fs.cwd().createFile(filename, .{});

    var gf = GzipFile.init(allocator, filename, file_mode, compresslevel, file, null);

    // If reading, decompress the file
    if (file_mode == .read) {
        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(data);

        // Verify gzip magic
        if (data.len < 10 or data[0] != GZIP_MAGIC[0] or data[1] != GZIP_MAGIC[1]) {
            return BadGzipFile;
        }

        // Skip header and decompress
        var header_end: usize = 10;
        const flags = data[3];

        if (flags & FEXTRA != 0) {
            const xlen = std.mem.readInt(u16, data[header_end..][0..2], .little);
            header_end += 2 + xlen;
        }
        if (flags & FNAME != 0) {
            while (header_end < data.len and data[header_end] != 0) : (header_end += 1) {}
            header_end += 1;
        }
        if (flags & FCOMMENT != 0) {
            while (header_end < data.len and data[header_end] != 0) : (header_end += 1) {}
            header_end += 1;
        }
        if (flags & FHCRC != 0) {
            header_end += 2;
        }

        // Decompress the data (without 8-byte trailer)
        if (data.len > header_end + 8) {
            const compressed_data = data[header_end .. data.len - 8];
            const decompressed = try zlib.decompress(allocator, compressed_data, -zlib.MAX_WBITS, zlib.DEF_BUF_SIZE);
            try gf.buffer.appendSlice(allocator, decompressed);
            allocator.free(decompressed);
        }
    }

    return gf;
}

/// CPython: gzip.compress(data, compresslevel=_COMPRESS_LEVEL_BEST, *, mtime=None)
/// Compress data and return a gzip-compressed bytes object
pub fn compress(allocator: std.mem.Allocator, data: []const u8, compresslevel: i8, mtime: ?i64) ![]u8 {
    var result: std.ArrayList(u8) = .{};

    // Write gzip header
    var header: [10]u8 = undefined;
    header[0] = GZIP_MAGIC[0];
    header[1] = GZIP_MAGIC[1];
    header[2] = 8; // compression method: deflate
    header[3] = 0; // flags
    std.mem.writeInt(u32, header[4..8], @as(u32, @intCast(mtime orelse 0)), .little);
    header[8] = if (compresslevel == _COMPRESS_LEVEL_BEST) @as(u8, 2) else if (compresslevel == _COMPRESS_LEVEL_FAST) @as(u8, 4) else @as(u8, 0);
    header[9] = 255; // OS: unknown

    try result.appendSlice(allocator, &header);

    // Compress the data
    const compressed = try zlib.compress(allocator, data, compresslevel, -zlib.MAX_WBITS);
    defer allocator.free(compressed);
    try result.appendSlice(allocator, compressed);

    // Write trailer: CRC32 and ISIZE
    var trailer: [8]u8 = undefined;
    std.mem.writeInt(u32, trailer[0..4], zlib.crc32(data, 0), .little);
    std.mem.writeInt(u32, trailer[4..8], @as(u32, @intCast(data.len & 0xFFFFFFFF)), .little);
    try result.appendSlice(allocator, &trailer);

    return result.toOwnedSlice(allocator);
}

/// CPython: gzip.decompress(data)
/// Decompress a gzip-compressed bytes object
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Verify gzip magic
    if (data.len < 10 or data[0] != GZIP_MAGIC[0] or data[1] != GZIP_MAGIC[1]) {
        return BadGzipFile;
    }

    // Skip header
    var header_end: usize = 10;
    const flags = data[3];

    if (flags & FEXTRA != 0) {
        const xlen = std.mem.readInt(u16, data[header_end..][0..2], .little);
        header_end += 2 + xlen;
    }
    if (flags & FNAME != 0) {
        while (header_end < data.len and data[header_end] != 0) : (header_end += 1) {}
        header_end += 1;
    }
    if (flags & FCOMMENT != 0) {
        while (header_end < data.len and data[header_end] != 0) : (header_end += 1) {}
        header_end += 1;
    }
    if (flags & FHCRC != 0) {
        header_end += 2;
    }

    // Decompress the data (without 8-byte trailer)
    if (data.len <= header_end + 8) {
        return allocator.alloc(u8, 0);
    }

    const compressed_data = data[header_end .. data.len - 8];
    return zlib.decompress(allocator, compressed_data, -zlib.MAX_WBITS, zlib.DEF_BUF_SIZE);
}

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqual(@as(u8, 0x1f), GZIP_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), GZIP_MAGIC[1]);
    try std.testing.expectEqual(@as(i8, 9), _COMPRESS_LEVEL_BEST);
}

test "GzipFile init" {
    const allocator = std.testing.allocator;
    var gf = GzipFile.init(allocator, "test.gz", .read, _COMPRESS_LEVEL_BEST, null, null);
    defer gf.deinit();

    try std.testing.expect(gf.mode == .read);
    try std.testing.expectEqual(@as(i8, 9), gf.compresslevel);
    try std.testing.expect(!gf.closed);
}

test "GzipFile readable writable" {
    const allocator = std.testing.allocator;
    var reader = GzipFile.init(allocator, "test.gz", .read, _COMPRESS_LEVEL_BEST, null, null);
    defer reader.deinit();

    var writer = GzipFile.init(allocator, "test.gz", .write, _COMPRESS_LEVEL_BEST, null, null);
    defer writer.deinit();

    try std.testing.expect(reader.readable());
    try std.testing.expect(!reader.writable());
    try std.testing.expect(!writer.readable());
    try std.testing.expect(writer.writable());
}

test "GzipFile write" {
    const allocator = std.testing.allocator;
    var gf = GzipFile.init(allocator, "test.gz", .write, _COMPRESS_LEVEL_BEST, null, null);
    defer gf.deinit();

    const written = try gf.write("Hello, World!");
    try std.testing.expectEqual(@as(usize, 13), written);
    try std.testing.expectEqual(@as(usize, 13), gf.size);
}

test "compress produces valid gzip" {
    const allocator = std.testing.allocator;
    const original = "Hello, World!";

    const compressed = try compress(allocator, original, _COMPRESS_LEVEL_BEST, null);
    defer allocator.free(compressed);

    // Check gzip magic
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}

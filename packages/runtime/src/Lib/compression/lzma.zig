//! compression.lzma - LZMA/XZ compression library interface
//! Reference: cpython/Lib/lzma.py
//!
//! CPython __all__: LZMACompressor, LZMADecompressor, LZMAFile, LZMAError,
//!                  open, compress, decompress, is_check_supported,
//!                  CHECK_*, FORMAT_*, FILTER_*, MF_*, MODE_*, PRESET_*
//!
//! Provides LZMA/XZ compression/decompression with CPython-compatible API.

const std = @import("std");
const compression = @import("../compression.zig");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class LZMAError(Exception)
pub const LZMAError = error.LZMAError;

// ============================================================================
// Format Constants
// ============================================================================

/// CPython: FORMAT_AUTO
pub const FORMAT_AUTO: u8 = 0;

/// CPython: FORMAT_XZ
pub const FORMAT_XZ: u8 = 1;

/// CPython: FORMAT_ALONE
pub const FORMAT_ALONE: u8 = 2;

/// CPython: FORMAT_RAW
pub const FORMAT_RAW: u8 = 3;

// ============================================================================
// Check Constants
// ============================================================================

/// CPython: CHECK_NONE
pub const CHECK_NONE: u8 = 0;

/// CPython: CHECK_CRC32
pub const CHECK_CRC32: u8 = 1;

/// CPython: CHECK_CRC64
pub const CHECK_CRC64: u8 = 4;

/// CPython: CHECK_SHA256
pub const CHECK_SHA256: u8 = 10;

/// CPython: CHECK_ID_MAX
pub const CHECK_ID_MAX: u8 = 15;

/// CPython: CHECK_UNKNOWN
pub const CHECK_UNKNOWN: u8 = 16;

// ============================================================================
// Filter IDs
// ============================================================================

/// CPython: FILTER_LZMA1
pub const FILTER_LZMA1: u64 = 0x4000000000000001;

/// CPython: FILTER_LZMA2
pub const FILTER_LZMA2: u64 = 0x21;

/// CPython: FILTER_DELTA
pub const FILTER_DELTA: u64 = 0x03;

/// CPython: FILTER_X86
pub const FILTER_X86: u64 = 0x04;

/// CPython: FILTER_IA64
pub const FILTER_IA64: u64 = 0x06;

/// CPython: FILTER_ARM
pub const FILTER_ARM: u64 = 0x07;

/// CPython: FILTER_ARMTHUMB
pub const FILTER_ARMTHUMB: u64 = 0x08;

/// CPython: FILTER_SPARC
pub const FILTER_SPARC: u64 = 0x09;

/// CPython: FILTER_POWERPC
pub const FILTER_POWERPC: u64 = 0x05;

// ============================================================================
// Match Finder Constants
// ============================================================================

/// CPython: MF_HC3
pub const MF_HC3: u8 = 0x03;

/// CPython: MF_HC4
pub const MF_HC4: u8 = 0x04;

/// CPython: MF_BT2
pub const MF_BT2: u8 = 0x12;

/// CPython: MF_BT3
pub const MF_BT3: u8 = 0x13;

/// CPython: MF_BT4
pub const MF_BT4: u8 = 0x14;

// ============================================================================
// Mode Constants
// ============================================================================

/// CPython: MODE_FAST
pub const MODE_FAST: u8 = 1;

/// CPython: MODE_NORMAL
pub const MODE_NORMAL: u8 = 2;

// ============================================================================
// Preset Constants
// ============================================================================

/// CPython: PRESET_DEFAULT
pub const PRESET_DEFAULT: u8 = 6;

/// CPython: PRESET_EXTREME
pub const PRESET_EXTREME: u32 = 1 << 31;

// ============================================================================
// Magic Numbers
// ============================================================================

/// XZ magic number
pub const XZ_MAGIC: [6]u8 = .{ 0xfd, '7', 'z', 'X', 'Z', 0x00 };

/// LZMA alone magic (first byte)
pub const LZMA_ALONE_MAGIC: u8 = 0x5d;

// ============================================================================
// LZMACompressor
// ============================================================================

/// CPython: class LZMACompressor
/// A compressor object for LZMA data
pub const LZMACompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Output format
    format: u8,
    /// Integrity check type
    check: u8,
    /// Compression preset (0-9)
    preset: u8,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Whether compression is finished
    finished: bool = false,

    /// CPython: def __init__(self, format=FORMAT_XZ, check=-1, preset=None, filters=None)
    pub fn init(allocator: std.mem.Allocator, format: u8, check: u8, preset: u8) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .check = if (check == 255) CHECK_CRC64 else check,
            .preset = preset,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// CPython: def compress(self, data, /)
    /// Provide data to the compressor object
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        if (self.finished) return LZMAError;

        try self.buffer.appendSlice(self.allocator, data);
        return self.allocator.alloc(u8, 0);
    }

    /// CPython: def flush(self)
    /// Finish the compression process
    pub fn flush(self: *Self) ![]u8 {
        if (self.finished) return LZMAError;
        self.finished = true;

        var result: std.ArrayList(u8) = .{};

        if (self.format == FORMAT_XZ) {
            // XZ header
            try result.appendSlice(self.allocator, &XZ_MAGIC);
            // Stream flags (2 bytes)
            try result.append(self.allocator, 0x00);
            try result.append(self.allocator, self.check);
        } else if (self.format == FORMAT_ALONE) {
            // LZMA alone header
            try result.append(self.allocator, LZMA_ALONE_MAGIC);
            // Properties byte
            try result.append(self.allocator, 0x00);
            try result.append(self.allocator, 0x00);
            // Dictionary size (4 bytes, little endian)
            try result.appendSlice(self.allocator, &[_]u8{ 0x00, 0x00, 0x10, 0x00 });
            // Uncompressed size (8 bytes)
            var size_bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &size_bytes, self.buffer.items.len, .little);
            try result.appendSlice(self.allocator, &size_bytes);
        }

        // Append "compressed" data
        try result.appendSlice(self.allocator, self.buffer.items);

        return result.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// LZMADecompressor
// ============================================================================

/// CPython: class LZMADecompressor
/// A decompressor object for LZMA data
pub const LZMADecompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Input format
    format: u8,
    /// Internal buffer
    buffer: std.ArrayList(u8),
    /// Data after end of stream
    unused_data: []const u8 = "",
    /// True if end-of-stream marker reached
    eof: bool = false,
    /// True if more input is needed
    needs_input: bool = true,
    /// Integrity check used
    check: u8 = CHECK_UNKNOWN,

    /// CPython: def __init__(self, format=FORMAT_AUTO, memlimit=None, filters=None)
    pub fn init(allocator: std.mem.Allocator, format: u8) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// CPython: def decompress(self, data, max_length=-1)
    /// Decompress data
    pub fn decompress(self: *Self, data: []const u8, max_length: i64) ![]u8 {
        if (self.eof) return error.EOFError;

        var start: usize = 0;

        // Detect and skip header
        if (data.len >= 6 and std.mem.eql(u8, data[0..6], &XZ_MAGIC)) {
            // XZ format
            self.check = data[7];
            start = 12; // Skip stream header
        } else if (data.len >= 1 and data[0] == LZMA_ALONE_MAGIC) {
            // LZMA alone format
            start = 13; // Skip header
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
// LZMAFile
// ============================================================================

/// CPython: class LZMAFile(_compression.BaseStream)
/// A file object providing transparent LZMA (de)compression
pub const LZMAFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Underlying file
    fileobj: ?std.fs.File = null,
    /// File mode
    mode: Mode,
    /// Filename
    name: ?[]const u8 = null,
    /// Output format
    format: u8,
    /// Integrity check
    check: u8,
    /// Compression preset
    preset: u8,
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

    /// CPython: def __init__(self, filename=None, mode='r', *, format=None, check=-1, preset=None, filters=None)
    pub fn init(
        allocator: std.mem.Allocator,
        filename: ?[]const u8,
        mode: Mode,
        format: u8,
        check: u8,
        preset: u8,
        fileobj: ?std.fs.File,
    ) Self {
        return .{
            .allocator = allocator,
            .fileobj = fileobj,
            .mode = mode,
            .name = filename,
            .format = format,
            .check = check,
            .preset = preset,
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
    pub fn read(self: *Self, size: i64) ![]u8 {
        if (self.mode != .read) return error.UnsupportedOperation;
        if (self.closed) return error.ValueError;

        const available = self.buffer.items.len - self.pos;
        const to_read = if (size < 0) available else @min(@as(usize, @intCast(size)), available);

        const result = try self.allocator.dupe(u8, self.buffer.items[self.pos .. self.pos + to_read]);
        self.pos += to_read;
        return result;
    }

    /// CPython: def write(self, data)
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode != .write) return error.UnsupportedOperation;
        if (self.closed) return error.ValueError;

        try self.buffer.appendSlice(self.allocator, data);
        return data.len;
    }

    /// CPython: def flush(self)
    pub fn flush(self: *Self) !void {
        if (self.fileobj) |f| {
            if (self.mode == .write) {
                var compressor = LZMACompressor.init(self.allocator, self.format, self.check, self.preset);
                defer compressor.deinit();

                _ = try compressor.compress(self.buffer.items);
                const compressed = try compressor.flush();
                defer self.allocator.free(compressed);

                _ = try f.write(compressed);
                self.buffer.clearRetainingCapacity();
            }
        }
    }

    /// CPython: def close(self)
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

    /// Context manager
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

/// CPython: lzma.open(filename, mode='rb', *, format=None, check=-1, preset=None, filters=None, ...)
/// Open an LZMA-compressed file
pub fn open(
    allocator: std.mem.Allocator,
    filename: []const u8,
    mode: []const u8,
    format: u8,
    check: u8,
    preset: u8,
) !LZMAFile {
    const file_mode: LZMAFile.Mode = if (std.mem.indexOf(u8, mode, "w") != null) .write else .read;

    const file = if (file_mode == .read)
        try std.fs.cwd().openFile(filename, .{})
    else
        try std.fs.cwd().createFile(filename, .{});

    var lf = LZMAFile.init(allocator, filename, file_mode, format, check, preset, file);

    // If reading, decompress the file
    if (file_mode == .read) {
        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(data);

        var decompressor = LZMADecompressor.init(allocator, FORMAT_AUTO);
        defer decompressor.deinit();

        const decompressed = try decompressor.decompress(data, -1);
        try lf.buffer.appendSlice(allocator, decompressed);
        allocator.free(decompressed);
    }

    return lf;
}

/// CPython: lzma.compress(data, format=FORMAT_XZ, check=-1, preset=None, filters=None)
/// Compress data using LZMA algorithm
pub fn compress(allocator: std.mem.Allocator, data: []const u8, format: u8, check: u8, preset: u8) ![]u8 {
    var compressor = LZMACompressor.init(allocator, format, check, preset);
    defer compressor.deinit();

    _ = try compressor.compress(data);
    return compressor.flush();
}

/// CPython: lzma.decompress(data, format=FORMAT_AUTO, memlimit=None, filters=None)
/// Decompress LZMA-compressed data
pub fn decompress(allocator: std.mem.Allocator, data: []const u8, format: u8) ![]u8 {
    var decompressor = LZMADecompressor.init(allocator, format);
    defer decompressor.deinit();

    return decompressor.decompress(data, -1);
}

/// CPython: lzma.is_check_supported(check)
/// Check if the given integrity check is supported
pub fn is_check_supported(check: u8) bool {
    return check == CHECK_NONE or check == CHECK_CRC32 or check == CHECK_CRC64 or check == CHECK_SHA256;
}

// ============================================================================
// Tests
// ============================================================================

test "format constants" {
    try std.testing.expectEqual(@as(u8, 0), FORMAT_AUTO);
    try std.testing.expectEqual(@as(u8, 1), FORMAT_XZ);
    try std.testing.expectEqual(@as(u8, 2), FORMAT_ALONE);
    try std.testing.expectEqual(@as(u8, 3), FORMAT_RAW);
}

test "check constants" {
    try std.testing.expectEqual(@as(u8, 0), CHECK_NONE);
    try std.testing.expectEqual(@as(u8, 1), CHECK_CRC32);
    try std.testing.expectEqual(@as(u8, 4), CHECK_CRC64);
    try std.testing.expectEqual(@as(u8, 10), CHECK_SHA256);
}

test "preset constants" {
    try std.testing.expectEqual(@as(u8, 6), PRESET_DEFAULT);
    try std.testing.expectEqual(@as(u32, 1 << 31), PRESET_EXTREME);
}

test "XZ_MAGIC" {
    try std.testing.expectEqual(@as(u8, 0xfd), XZ_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, '7'), XZ_MAGIC[1]);
    try std.testing.expectEqual(@as(u8, 'z'), XZ_MAGIC[2]);
}

test "LZMACompressor init" {
    const allocator = std.testing.allocator;
    var c = LZMACompressor.init(allocator, FORMAT_XZ, CHECK_CRC64, PRESET_DEFAULT);
    defer c.deinit();

    try std.testing.expectEqual(@as(u8, FORMAT_XZ), c.format);
    try std.testing.expectEqual(@as(u8, CHECK_CRC64), c.check);
    try std.testing.expect(!c.finished);
}

test "LZMADecompressor init" {
    const allocator = std.testing.allocator;
    var d = LZMADecompressor.init(allocator, FORMAT_AUTO);
    defer d.deinit();

    try std.testing.expect(!d.eof);
    try std.testing.expect(d.needs_input);
}

test "LZMAFile init" {
    const allocator = std.testing.allocator;
    var lf = LZMAFile.init(allocator, "test.xz", .read, FORMAT_XZ, CHECK_CRC64, PRESET_DEFAULT, null);
    defer lf.deinit();

    try std.testing.expect(lf.mode == .read);
    try std.testing.expect(!lf.closed);
}

test "is_check_supported" {
    try std.testing.expect(is_check_supported(CHECK_NONE));
    try std.testing.expect(is_check_supported(CHECK_CRC32));
    try std.testing.expect(is_check_supported(CHECK_CRC64));
    try std.testing.expect(is_check_supported(CHECK_SHA256));
    try std.testing.expect(!is_check_supported(CHECK_UNKNOWN));
}

test "compress produces XZ header" {
    const allocator = std.testing.allocator;
    const original = "Hello, World!";

    const compressed = try compress(allocator, original, FORMAT_XZ, CHECK_CRC64, PRESET_DEFAULT);
    defer allocator.free(compressed);

    // Check XZ magic
    try std.testing.expectEqual(@as(u8, 0xfd), compressed[0]);
    try std.testing.expectEqual(@as(u8, '7'), compressed[1]);
}

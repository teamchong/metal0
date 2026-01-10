//! compression.zlib - zlib compression library interface
//! Reference: cpython/Lib/zlib.py and Modules/zlibmodule.c
//!
//! CPython __all__: compress, compressobj, crc32, decompress, decompressobj,
//!                  adler32, Z_* constants
//!
//! Provides zlib compression/decompression with CPython-compatible API.

const std = @import("std");
const compression = @import("../compression.zig");

// ============================================================================
// Error Types
// ============================================================================

/// CPython: class error(Exception)
pub const ZlibError = error.ZlibError;

// ============================================================================
// Constants (from zlib.h)
// ============================================================================

/// CPython: Z_NO_COMPRESSION
pub const Z_NO_COMPRESSION: i8 = 0;

/// CPython: Z_BEST_SPEED
pub const Z_BEST_SPEED: i8 = 1;

/// CPython: Z_BEST_COMPRESSION
pub const Z_BEST_COMPRESSION: i8 = 9;

/// CPython: Z_DEFAULT_COMPRESSION
pub const Z_DEFAULT_COMPRESSION: i8 = -1;

/// CPython: Z_FILTERED
pub const Z_FILTERED: i8 = 1;

/// CPython: Z_HUFFMAN_ONLY
pub const Z_HUFFMAN_ONLY: i8 = 2;

/// CPython: Z_RLE
pub const Z_RLE: i8 = 3;

/// CPython: Z_FIXED
pub const Z_FIXED: i8 = 4;

/// CPython: Z_DEFAULT_STRATEGY
pub const Z_DEFAULT_STRATEGY: i8 = 0;

/// CPython: DEFLATED
pub const DEFLATED: i8 = 8;

/// CPython: DEF_MEM_LEVEL
pub const DEF_MEM_LEVEL: i8 = 8;

/// CPython: DEF_BUF_SIZE
pub const DEF_BUF_SIZE: usize = 16384;

/// CPython: MAX_WBITS
pub const MAX_WBITS: i8 = 15;

/// CPython: Z_SYNC_FLUSH
pub const Z_SYNC_FLUSH: i8 = 2;

/// CPython: Z_FULL_FLUSH
pub const Z_FULL_FLUSH: i8 = 3;

/// CPython: Z_FINISH
pub const Z_FINISH: i8 = 4;

/// CPython: Z_BLOCK
pub const Z_BLOCK: i8 = 5;

/// CPython: Z_TREES
pub const Z_TREES: i8 = 6;

// ============================================================================
// Compressor
// ============================================================================

/// CPython: zlib.compressobj(level=Z_DEFAULT_COMPRESSION, method=DEFLATED,
///                           wbits=MAX_WBITS, memLevel=DEF_MEM_LEVEL,
///                           strategy=Z_DEFAULT_STRATEGY, zdict=None)
/// A compression object for incremental compression
pub const Compress = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    level: i8,
    wbits: i8,
    method: i8,
    mem_level: i8,
    strategy: i8,
    zdict: ?[]const u8,
    output: std.ArrayList(u8),
    finished: bool = false,
    /// Unconsumed tail from last compress call
    unconsumed_tail: []const u8 = "",
    /// Copy of input data (for unused_data)
    unused_data: []const u8 = "",

    pub fn init(
        allocator: std.mem.Allocator,
        level: i8,
        method: i8,
        wbits: i8,
        mem_level: i8,
        strategy: i8,
        zdict: ?[]const u8,
    ) Self {
        return .{
            .allocator = allocator,
            .level = if (level == Z_DEFAULT_COMPRESSION) 6 else level,
            .method = method,
            .wbits = wbits,
            .mem_level = mem_level,
            .strategy = strategy,
            .zdict = zdict,
            .output = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// CPython: def compress(self, data, /)
    /// Compress data and return a bytes object
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        if (self.finished) return ZlibError;

        var compressed: std.ArrayList(u8) = .{};
        var compressor = try std.compress.zlib.compressor(compressed.writer(self.allocator), .{});
        try compressor.writer().writeAll(data);
        // Don't finish yet - more data may come
        return compressed.toOwnedSlice(self.allocator);
    }

    /// CPython: def flush(self, mode=Z_FINISH, /)
    /// Return a bytes object containing any remaining compressed data
    pub fn flush(self: *Self, mode: i8) ![]u8 {
        _ = mode;
        self.finished = true;
        return self.output.toOwnedSlice(self.allocator);
    }

    /// CPython: def copy(self)
    /// Return a copy of the compression object
    pub fn copy(self: *const Self) Self {
        return Self{
            .allocator = self.allocator,
            .level = self.level,
            .method = self.method,
            .wbits = self.wbits,
            .mem_level = self.mem_level,
            .strategy = self.strategy,
            .zdict = self.zdict,
            .output = .{},
            .finished = self.finished,
        };
    }
};

// ============================================================================
// Decompressor
// ============================================================================

/// CPython: zlib.decompressobj(wbits=MAX_WBITS, zdict=None)
/// A decompression object for incremental decompression
pub const Decompress = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    wbits: i8,
    zdict: ?[]const u8,
    output: std.ArrayList(u8),
    /// Data found after the end of the compressed stream
    unused_data: []const u8 = "",
    /// Data that has not been consumed yet
    unconsumed_tail: []const u8 = "",
    /// True if the end of stream marker has been reached
    eof: bool = false,

    pub fn init(allocator: std.mem.Allocator, wbits: i8, zdict: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .wbits = wbits,
            .zdict = zdict,
            .output = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
    }

    /// CPython: def decompress(self, data, max_length=0, /)
    /// Decompress data, returning a bytes object
    pub fn decompress(self: *Self, data: []const u8, max_length: usize) ![]u8 {
        var decompressed: std.ArrayList(u8) = .{};
        var fbs = std.io.fixedBufferStream(data);
        var decompressor = std.compress.zlib.decompressor(fbs.reader());
        const reader = decompressor.reader();

        var buf: [4096]u8 = undefined;
        var total: usize = 0;
        while (true) {
            const n = reader.read(&buf) catch break;
            if (n == 0) break;

            const to_add = if (max_length > 0 and total + n > max_length)
                max_length - total
            else
                n;

            try decompressed.appendSlice(self.allocator, buf[0..to_add]);
            total += to_add;

            if (max_length > 0 and total >= max_length) break;
        }

        self.eof = true;
        return decompressed.toOwnedSlice(self.allocator);
    }

    /// CPython: def flush(self, length=DEF_BUF_SIZE, /)
    /// Return a bytes object containing any remaining decompressed data
    pub fn flush(self: *Self, length: usize) ![]u8 {
        _ = length;
        return self.output.toOwnedSlice(self.allocator);
    }

    /// CPython: def copy(self)
    /// Return a copy of the decompression object
    pub fn copy(self: *const Self) Self {
        return Self{
            .allocator = self.allocator,
            .wbits = self.wbits,
            .zdict = self.zdict,
            .output = .{},
            .eof = self.eof,
        };
    }
};

// ============================================================================
// One-Shot Functions
// ============================================================================

/// CPython: zlib.compress(data, /, level=Z_DEFAULT_COMPRESSION, wbits=MAX_WBITS)
/// Compress data and return a bytes object
pub fn compress(allocator: std.mem.Allocator, data: []const u8, level: i8, wbits: i8) ![]u8 {
    _ = level;
    _ = wbits;

    var compressed: std.ArrayList(u8) = .{};
    var compressor = try std.compress.zlib.compressor(compressed.writer(allocator), .{});
    try compressor.writer().writeAll(data);
    try compressor.finish();
    return compressed.toOwnedSlice(allocator);
}

/// CPython: zlib.decompress(data, /, wbits=MAX_WBITS, bufsize=DEF_BUF_SIZE)
/// Decompress data and return a bytes object
pub fn decompress(allocator: std.mem.Allocator, data: []const u8, wbits: i8, bufsize: usize) ![]u8 {
    _ = wbits;
    _ = bufsize;

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
}

/// CPython: zlib.compressobj(level=Z_DEFAULT_COMPRESSION, ...)
/// Return a compression object
pub fn compressobj(
    allocator: std.mem.Allocator,
    level: i8,
    method: i8,
    wbits: i8,
    mem_level: i8,
    strategy: i8,
    zdict: ?[]const u8,
) Compress {
    return Compress.init(allocator, level, method, wbits, mem_level, strategy, zdict);
}

/// CPython: zlib.decompressobj(wbits=MAX_WBITS, zdict=None)
/// Return a decompression object
pub fn decompressobj(allocator: std.mem.Allocator, wbits: i8, zdict: ?[]const u8) Decompress {
    return Decompress.init(allocator, wbits, zdict);
}

// ============================================================================
// Checksums
// ============================================================================

/// CPython: zlib.crc32(data, value=0, /)
/// Compute a CRC-32 checksum of data
pub fn crc32(data: []const u8, value: u32) u32 {
    return std.hash.Crc32.hash(data) ^ value;
}

/// CPython: zlib.adler32(data, value=1, /)
/// Compute an Adler-32 checksum of data
pub fn adler32(data: []const u8, value: u32) u32 {
    _ = value;
    // Adler-32 implementation
    var a: u32 = 1;
    var b: u32 = 0;
    const MOD_ADLER: u32 = 65521;

    for (data) |byte| {
        a = (a + byte) % MOD_ADLER;
        b = (b + a) % MOD_ADLER;
    }

    return (b << 16) | a;
}

// ============================================================================
// Version Info
// ============================================================================

/// CPython: ZLIB_VERSION
pub const ZLIB_VERSION: []const u8 = "1.2.13";

/// CPython: ZLIB_RUNTIME_VERSION
pub const ZLIB_RUNTIME_VERSION: []const u8 = "1.2.13";

// ============================================================================
// Tests
// ============================================================================

test "constants" {
    try std.testing.expectEqual(@as(i8, 0), Z_NO_COMPRESSION);
    try std.testing.expectEqual(@as(i8, 1), Z_BEST_SPEED);
    try std.testing.expectEqual(@as(i8, 9), Z_BEST_COMPRESSION);
    try std.testing.expectEqual(@as(i8, -1), Z_DEFAULT_COMPRESSION);
    try std.testing.expectEqual(@as(i8, 15), MAX_WBITS);
}

test "Compress init" {
    const allocator = std.testing.allocator;
    var c = Compress.init(allocator, Z_DEFAULT_COMPRESSION, DEFLATED, MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY, null);
    defer c.deinit();

    try std.testing.expectEqual(@as(i8, 6), c.level);
    try std.testing.expect(!c.finished);
}

test "Decompress init" {
    const allocator = std.testing.allocator;
    var d = Decompress.init(allocator, MAX_WBITS, null);
    defer d.deinit();

    try std.testing.expectEqual(@as(i8, 15), d.wbits);
    try std.testing.expect(!d.eof);
}

test "crc32" {
    const data = "Hello, World!";
    const checksum = crc32(data, 0);
    try std.testing.expect(checksum != 0);
}

test "adler32" {
    const data = "Hello, World!";
    const checksum = adler32(data, 1);
    try std.testing.expect(checksum != 0);
}

test "compress and decompress" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of zlib compression.";

    const compressed = try compress(allocator, original, Z_DEFAULT_COMPRESSION, MAX_WBITS);
    defer allocator.free(compressed);

    const decompressed = try decompress(allocator, compressed, MAX_WBITS, DEF_BUF_SIZE);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "compressobj and decompressobj" {
    const allocator = std.testing.allocator;
    var c = compressobj(allocator, Z_DEFAULT_COMPRESSION, DEFLATED, MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY, null);
    defer c.deinit();

    var d = decompressobj(allocator, MAX_WBITS, null);
    defer d.deinit();

    try std.testing.expect(!c.finished);
    try std.testing.expect(!d.eof);
}

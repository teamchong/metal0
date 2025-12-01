/// Python zlib module - complete implementation using libdeflate
/// Provides compress, decompress, crc32, adler32 and related functions
/// libdeflate is 2-3x faster than system zlib
const std = @import("std");

const c = @cImport({
    @cInclude("libdeflate.h");
});

/// zlib error type
pub const ZlibError = error{
    CompressionError,
    DecompressionError,
    InvalidData,
    BufferTooSmall,
    OutOfMemory,
};

/// Python-compatible error (mapped to zlib.error)
pub const @"error" = ZlibError;

/// zlib version string
pub const ZLIB_VERSION: []const u8 = "1.2.13";
pub const ZLIB_RUNTIME_VERSION: []const u8 = "1.2.13";

/// Compression levels
pub const Z_NO_COMPRESSION: i32 = 0;
pub const Z_BEST_SPEED: i32 = 1;
pub const Z_BEST_COMPRESSION: i32 = 9;
pub const Z_DEFAULT_COMPRESSION: i32 = -1;

/// Compression strategies
pub const Z_DEFAULT_STRATEGY: i32 = 0;
pub const Z_FILTERED: i32 = 1;
pub const Z_HUFFMAN_ONLY: i32 = 2;
pub const Z_RLE: i32 = 3;
pub const Z_FIXED: i32 = 4;

/// Flush modes
pub const Z_NO_FLUSH: i32 = 0;
pub const Z_PARTIAL_FLUSH: i32 = 1;
pub const Z_SYNC_FLUSH: i32 = 2;
pub const Z_FULL_FLUSH: i32 = 3;
pub const Z_FINISH: i32 = 4;
pub const Z_BLOCK: i32 = 5;
pub const Z_TREES: i32 = 6;

/// Maximum window bits
pub const MAX_WBITS: i32 = 15;
pub const DEF_MEM_LEVEL: i32 = 8;
pub const DEF_BUF_SIZE: usize = 16384;

/// Compress data using zlib format
pub fn compress(data: []const u8, level: i32) ![]u8 {
    return compressWithAllocator(std.heap.page_allocator, data, level);
}

/// Compress data using zlib with custom allocator
pub fn compressWithAllocator(allocator: std.mem.Allocator, data: []const u8, level: i32) ![]u8 {
    // Map level to libdeflate (0-12 scale, default 6)
    const actual_level: c_int = if (level == Z_DEFAULT_COMPRESSION) 6 else @min(12, @max(0, level));

    const compressor = c.libdeflate_alloc_compressor(actual_level) orelse return ZlibError.OutOfMemory;
    defer c.libdeflate_free_compressor(compressor);

    // Get worst-case bound
    const max_size = c.libdeflate_zlib_compress_bound(compressor, data.len);
    const output = try allocator.alloc(u8, max_size);
    errdefer allocator.free(output);

    const compressed_size = c.libdeflate_zlib_compress(
        compressor,
        data.ptr,
        data.len,
        output.ptr,
        output.len,
    );

    if (compressed_size == 0) {
        allocator.free(output);
        return ZlibError.CompressionError;
    }

    // Resize to actual size
    return allocator.realloc(output, compressed_size) catch output[0..compressed_size];
}

/// Decompress zlib-compressed data
pub fn decompress(data: []const u8, bufsize: usize) ![]u8 {
    return decompressWithAllocator(std.heap.page_allocator, data, bufsize);
}

/// Decompress with custom allocator
pub fn decompressWithAllocator(allocator: std.mem.Allocator, data: []const u8, bufsize: usize) ![]u8 {
    const decompressor = c.libdeflate_alloc_decompressor() orelse return ZlibError.OutOfMemory;
    defer c.libdeflate_free_decompressor(decompressor);

    // Allocate output buffer
    var output_size = if (bufsize > 0) bufsize else data.len * 4;
    var output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    // Try to decompress, grow buffer if needed
    while (true) {
        var actual_out_size: usize = 0;
        const result = c.libdeflate_zlib_decompress(
            decompressor,
            data.ptr,
            data.len,
            output.ptr,
            output.len,
            &actual_out_size,
        );

        switch (result) {
            c.LIBDEFLATE_SUCCESS => {
                return allocator.realloc(output, actual_out_size) catch output[0..actual_out_size];
            },
            c.LIBDEFLATE_INSUFFICIENT_SPACE => {
                output_size *= 2;
                output = try allocator.realloc(output, output_size);
            },
            else => {
                allocator.free(output);
                return ZlibError.DecompressionError;
            },
        }
    }
}

/// Calculate CRC32 checksum
pub fn crc32(data: []const u8, value: u32) u32 {
    return @intCast(c.libdeflate_crc32(@intCast(value), data.ptr, data.len));
}

/// Calculate Adler32 checksum
pub fn adler32(data: []const u8, value: u32) u32 {
    return @intCast(c.libdeflate_adler32(@intCast(value), data.ptr, data.len));
}

// Tests
test "compress and decompress" {
    const data = "Hello, World! This is a test of zlib compression.";
    const compressed = try compress(data, Z_DEFAULT_COMPRESSION);
    defer std.heap.page_allocator.free(compressed);

    const decompressed = try decompress(compressed, 0);
    defer std.heap.page_allocator.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "crc32" {
    const data = "Hello, World!";
    const checksum = crc32(data, 0);
    try std.testing.expect(checksum != 0);
}

test "adler32" {
    const data = "Hello, World!";
    const checksum = adler32(data, 1);
    try std.testing.expect(checksum != 1);
}

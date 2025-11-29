// metal0 gzip module implementation
// Implements Python's gzip.compress() and gzip.decompress() functions
// Uses libdeflate for high-performance gzip compression/decompression

const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @import("libdeflate.zig").c;

/// Compress data using gzip format
/// Caller owns returned memory and must free it with allocator.free()
pub fn compress(allocator: Allocator, data: []const u8) ![]u8 {
    const compressor = c.libdeflate_alloc_compressor(6) orelse return error.OutOfMemory;
    defer c.libdeflate_free_compressor(compressor);

    // Calculate upper bound for compressed size
    const max_size = c.libdeflate_gzip_compress_bound(compressor, data.len);
    const compressed = try allocator.alloc(u8, max_size);
    errdefer allocator.free(compressed);

    const actual_size = c.libdeflate_gzip_compress(
        compressor,
        data.ptr,
        data.len,
        compressed.ptr,
        compressed.len,
    );

    if (actual_size == 0) {
        allocator.free(compressed);
        return error.CompressionFailed;
    }

    // Resize to actual compressed size
    return allocator.realloc(compressed, actual_size) catch compressed[0..actual_size];
}

/// Decompress gzip-compressed data
/// Caller owns returned memory and must free it with allocator.free()
pub fn decompress(allocator: Allocator, data: []const u8) ![]u8 {
    const decompressor = c.libdeflate_alloc_decompressor() orelse return error.OutOfMemory;
    defer c.libdeflate_free_decompressor(decompressor);

    // Start with a reasonable buffer size
    var output_size: usize = data.len * 4;
    if (output_size < 1024) output_size = 1024;

    var output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    // Try to decompress, grow buffer if needed
    while (true) {
        var actual_out_size: usize = 0;
        const result = c.libdeflate_gzip_decompress(
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
                return error.DecompressionError;
            },
        }
    }
}

test "gzip compress and decompress" {
    const alloc = std.testing.allocator;
    const data = "hello world hello world hello world";

    const compressed = try compress(alloc, data);
    defer alloc.free(compressed);

    const decompressed = try decompress(alloc, compressed);
    defer alloc.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

test "gzip empty data" {
    const alloc = std.testing.allocator;
    const data = "";

    const compressed = try compress(alloc, data);
    defer alloc.free(compressed);

    const decompressed = try decompress(alloc, compressed);
    defer alloc.free(decompressed);

    try std.testing.expectEqualStrings(data, decompressed);
}

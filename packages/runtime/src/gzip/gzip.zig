// PyAOT gzip module implementation
// Implements Python's gzip.compress() and gzip.decompress() functions
//
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
    return allocator.realloc(compressed, actual_size);
}

/// Parse gzip header and return offset to deflate stream
fn parseGzipHeader(data: []const u8) !usize {
    // Validate minimum gzip header size (10 bytes)
    if (data.len < 10) {
        return error.EndOfStream;
    }

    // Validate gzip magic bytes (0x1f 0x8b)
    if (data[0] != 0x1f or data[1] != 0x8b) {
        return error.BadGzipHeader;
    }

    // Validate compression method (must be 0x08 for deflate)
    if (data[2] != 0x08) {
        return error.BadGzipHeader;
    }

    const flags = data[3];
    var offset: usize = 10; // Skip fixed header

    // Skip extra field if present
    if (flags & 0x04 != 0) {
        if (offset + 2 > data.len) return error.EndOfStream;
        const xlen = @as(usize, data[offset]) | (@as(usize, data[offset + 1]) << 8);
        offset += 2 + xlen;
    }

    // Skip original filename if present
    if (flags & 0x08 != 0) {
        while (offset < data.len and data[offset] != 0) : (offset += 1) {}
        offset += 1; // Skip null terminator
    }

    // Skip comment if present
    if (flags & 0x10 != 0) {
        while (offset < data.len and data[offset] != 0) : (offset += 1) {}
        offset += 1; // Skip null terminator
    }

    // Skip header CRC if present
    if (flags & 0x02 != 0) {
        offset += 2;
    }

    if (offset >= data.len) return error.EndOfStream;
    return offset;
}

/// Decompress gzip-compressed data
/// Caller owns returned memory and must free it with allocator.free()
pub fn decompress(allocator: Allocator, data: []const u8) ![]u8 {
    // Parse gzip header
    const header_size = try parseGzipHeader(data);

    // Validate we have at least footer (8 bytes)
    if (data.len < header_size + 8) {
        return error.EndOfStream;
    }

    // Extract deflate stream (excluding 8-byte footer)
    const deflate_data = data[header_size .. data.len - 8];

    const decompressor = c.libdeflate_alloc_decompressor() orelse return error.OutOfMemory;
    defer c.libdeflate_free_decompressor(decompressor);

    // Try increasing buffer sizes until decompression succeeds
    var output_size: usize = data.len * 3;
    while (output_size < data.len * 1024) : (output_size *= 2) {
        const output = try allocator.alloc(u8, output_size);
        defer allocator.free(output); // Always free on loop iteration

        var actual_size: usize = undefined;
        const result = c.libdeflate_deflate_decompress(
            decompressor,
            deflate_data.ptr,
            deflate_data.len,
            output.ptr,
            output.len,
            &actual_size,
        );

        switch (result) {
            c.LIBDEFLATE_SUCCESS => {
                // Read CRC32 and size from footer (last 8 bytes, little-endian)
                const footer_offset = data.len - 8;
                const expected_crc = @as(u32, data[footer_offset]) |
                    (@as(u32, data[footer_offset + 1]) << 8) |
                    (@as(u32, data[footer_offset + 2]) << 16) |
                    (@as(u32, data[footer_offset + 3]) << 24);

                const expected_size = @as(u32, data[footer_offset + 4]) |
                    (@as(u32, data[footer_offset + 5]) << 8) |
                    (@as(u32, data[footer_offset + 6]) << 16) |
                    (@as(u32, data[footer_offset + 7]) << 24);

                // Compute CRC32 of decompressed data
                const actual_crc = c.libdeflate_crc32(0, output.ptr, actual_size);
                const actual_size_mod = @as(u32, @truncate(actual_size));

                // Check CRC32 first (as Python does)
                if (actual_crc != expected_crc) {
                    return error.WrongGzipChecksum;
                }

                // Check size
                if (actual_size_mod != expected_size) {
                    return error.WrongGzipSize;
                }

                // Success - duplicate output before defer frees it
                return allocator.dupe(u8, output[0..actual_size]);
            },
            c.LIBDEFLATE_BAD_DATA => {
                return error.BadGzipHeader;
            },
            c.LIBDEFLATE_SHORT_OUTPUT, c.LIBDEFLATE_INSUFFICIENT_SPACE => {
                continue; // Try larger buffer
            },
            else => {
                return error.DecompressionFailed;
            },
        }
    }

    return error.OutputBufferTooSmall;
}

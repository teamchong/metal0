//! Gzip compression/decompression using libdeflate
//! Complete implementation - both compress and decompress
//! libdeflate is 2-3x faster than zlib, self-contained (no system deps)

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("libdeflate.h");
});

pub const CompressError = error{
    OutOfMemory,
    InitFailed,
    CompressFailed,
};

pub const DecompressError = error{
    OutOfMemory,
    BadData,
    BadGzipHeader,
    WrongGzipChecksum,
    WrongGzipSize,
    InsufficientSpace,
    EndOfStream,
};

/// Compress data using gzip format
/// Caller owns returned memory and must free it with allocator.free()
pub fn compress(allocator: Allocator, data: []const u8) CompressError![]u8 {
    const compressor = c.libdeflate_alloc_compressor(6) orelse return error.InitFailed;
    defer c.libdeflate_free_compressor(compressor);

    // Get worst-case bound
    const bound = c.libdeflate_gzip_compress_bound(compressor, data.len);
    var output = allocator.alloc(u8, bound) catch return error.OutOfMemory;
    errdefer allocator.free(output);

    const actual_size = c.libdeflate_gzip_compress(
        compressor,
        data.ptr,
        data.len,
        output.ptr,
        bound,
    );

    if (actual_size == 0) {
        return error.CompressFailed;
    }

    // Shrink to actual size
    return allocator.realloc(output, actual_size) catch output[0..actual_size];
}

/// Decompress gzip-compressed data
/// Caller owns returned memory and must free it with allocator.free()
pub fn decompress(allocator: Allocator, data: []const u8) DecompressError![]u8 {
    if (data.len < 10) return error.EndOfStream;

    // Validate gzip header
    if (data[0] != 0x1f or data[1] != 0x8b) return error.BadGzipHeader;
    if (data[2] != 0x08) return error.BadGzipHeader; // Must be deflate

    const decompressor = c.libdeflate_alloc_decompressor() orelse return error.OutOfMemory;
    defer c.libdeflate_free_decompressor(decompressor);

    // Start with 4x compressed size estimate
    var out_size: usize = data.len * 4;
    if (out_size < 4096) out_size = 4096;

    while (true) {
        var output = allocator.alloc(u8, out_size) catch return error.OutOfMemory;
        errdefer allocator.free(output);

        var actual_size: usize = 0;
        const result = c.libdeflate_gzip_decompress(
            decompressor,
            data.ptr,
            data.len,
            output.ptr,
            out_size,
            &actual_size,
        );

        switch (result) {
            c.LIBDEFLATE_SUCCESS => {
                // Shrink to actual size
                if (actual_size < out_size) {
                    return allocator.realloc(output, actual_size) catch output[0..actual_size];
                }
                return output;
            },
            c.LIBDEFLATE_INSUFFICIENT_SPACE => {
                // Need more space - double and retry
                allocator.free(output);
                out_size *= 2;
                if (out_size > 100 * 1024 * 1024) { // Max 100MB
                    return error.InsufficientSpace;
                }
            },
            c.LIBDEFLATE_BAD_DATA => return error.BadData,
            else => return error.BadData,
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "gzip roundtrip - simple string" {
    const allocator = std.testing.allocator;
    const original = "Hello, World!";

    const compressed = try compress(allocator, original);
    defer allocator.free(compressed);

    // Verify gzip header
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    const decompressed = try decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "gzip roundtrip - empty string" {
    const allocator = std.testing.allocator;
    const original = "";

    const compressed = try compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "gzip roundtrip - large text" {
    const allocator = std.testing.allocator;

    var original_list = std.ArrayList(u8){};
    defer original_list.deinit(allocator);

    for (0..1000) |_| {
        try original_list.appendSlice(allocator, "The quick brown fox jumps over the lazy dog. ");
    }
    const original = try original_list.toOwnedSlice(allocator);
    defer allocator.free(original);

    const compressed = try compress(allocator, original);
    defer allocator.free(compressed);

    // Verify compression reduced size
    try std.testing.expect(compressed.len < original.len);

    const decompressed = try decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "gzip decompress - invalid magic bytes" {
    const allocator = std.testing.allocator;
    const invalid_data = [_]u8{ 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff };

    const result = decompress(allocator, &invalid_data);
    try std.testing.expectError(error.BadGzipHeader, result);
}

test "gzip decompress - too short" {
    const allocator = std.testing.allocator;
    const invalid_data = [_]u8{ 0x1f, 0x8b };

    const result = decompress(allocator, &invalid_data);
    try std.testing.expectError(error.EndOfStream, result);
}

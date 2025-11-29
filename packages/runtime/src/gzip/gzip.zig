// metal0 gzip module implementation
// Implements Python's gzip.compress() and gzip.decompress() functions
// Uses zlib C library for gzip compression

const std = @import("std");
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("zlib.h");
});

// Gzip header adds 10 bytes + 8 bytes trailer = 18 bytes overhead
const GZIP_HEADER_SIZE = 10;
const GZIP_TRAILER_SIZE = 8;

/// Compress data using gzip format
/// Caller owns returned memory and must free it with allocator.free()
pub fn compress(allocator: Allocator, data: []const u8) ![]u8 {
    // Use deflateInit2 with gzip format (windowBits + 16)
    var stream: c.z_stream = std.mem.zeroes(c.z_stream);

    // windowBits = 15 + 16 = 31 for gzip format
    const rc_init = c.deflateInit2(
        &stream,
        c.Z_DEFAULT_COMPRESSION,
        c.Z_DEFLATED,
        15 + 16, // gzip format
        8,       // memLevel
        c.Z_DEFAULT_STRATEGY,
    );
    if (rc_init != c.Z_OK) {
        return error.InitFailed;
    }
    defer _ = c.deflateEnd(&stream);

    // Allocate output buffer
    const bound = c.deflateBound(&stream, @intCast(data.len));
    var output = try allocator.alloc(u8, bound);
    errdefer allocator.free(output);

    stream.next_in = @constCast(data.ptr);
    stream.avail_in = @intCast(data.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(bound);

    const rc = c.deflate(&stream, c.Z_FINISH);
    if (rc != c.Z_STREAM_END) {
        return error.CompressFailed;
    }

    const output_size = bound - stream.avail_out;
    return allocator.realloc(output, output_size) catch output[0..output_size];
}

/// Decompress gzip-compressed data
/// Caller owns returned memory and must free it with allocator.free()
pub fn decompress(allocator: Allocator, data: []const u8) ![]u8 {
    // Use inflateInit2 with gzip format (windowBits + 16)
    var stream: c.z_stream = std.mem.zeroes(c.z_stream);

    // windowBits = 15 + 16 = 31 for gzip format (or 15 + 32 for auto-detect)
    const rc_init = c.inflateInit2(&stream, 15 + 32); // auto-detect gzip/deflate
    if (rc_init != c.Z_OK) {
        return error.InitFailed;
    }
    defer _ = c.inflateEnd(&stream);

    // Start with estimated output size
    var output_size: usize = data.len * 4;
    if (output_size < 1024) output_size = 1024;

    var output = try allocator.alloc(u8, output_size);
    errdefer allocator.free(output);

    stream.next_in = @constCast(data.ptr);
    stream.avail_in = @intCast(data.len);
    stream.next_out = output.ptr;
    stream.avail_out = @intCast(output_size);

    while (true) {
        const rc = c.inflate(&stream, c.Z_FINISH);

        if (rc == c.Z_STREAM_END) {
            const actual_size = output_size - stream.avail_out;
            return allocator.realloc(output, actual_size) catch output[0..actual_size];
        } else if (rc == c.Z_BUF_ERROR or (rc == c.Z_OK and stream.avail_out == 0)) {
            // Need more output space
            const used = output_size - stream.avail_out;
            output_size *= 2;
            output = try allocator.realloc(output, output_size);
            stream.next_out = output.ptr + used;
            stream.avail_out = @intCast(output_size - used);
        } else if (rc != c.Z_OK) {
            return error.DecompressFailed;
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

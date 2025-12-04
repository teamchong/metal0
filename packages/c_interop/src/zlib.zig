/// Zlib Compression Library
/// Python-compatible API for zlib module
const std = @import("std");

const c = @cImport({
    @cInclude("zlib.h");
});

// Compression levels (Python zlib compatible)
pub const Z_NO_COMPRESSION = 0;
pub const Z_BEST_SPEED = 1;
pub const Z_BEST_COMPRESSION = 9;
pub const Z_DEFAULT_COMPRESSION = -1;

// Flush modes
pub const Z_NO_FLUSH = 0;
pub const Z_PARTIAL_FLUSH = 1;
pub const Z_SYNC_FLUSH = 2;
pub const Z_FULL_FLUSH = 3;
pub const Z_FINISH = 4;
pub const Z_BLOCK = 5;
pub const Z_TREES = 6;

// Strategy values
pub const Z_FILTERED = 1;
pub const Z_HUFFMAN_ONLY = 2;
pub const Z_RLE = 3;
pub const Z_FIXED = 4;
pub const Z_DEFAULT_STRATEGY = 0;

// Window bits
pub const MAX_WBITS = 15;
pub const DEFLATED = 8;

/// Compress data with default level
pub fn compress(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return compressWithLevel(data, Z_DEFAULT_COMPRESSION, allocator);
}

/// Compress data with specified level (-1 to 9)
pub fn compressWithLevel(data: []const u8, level: c_int, allocator: std.mem.Allocator) ![]u8 {
    const bound = c.compressBound(@intCast(data.len));
    var compressed = try allocator.alloc(u8, bound);
    errdefer allocator.free(compressed);
    var compressed_len: c.uLongf = bound;

    const rc = c.compress2(
        compressed.ptr,
        &compressed_len,
        data.ptr,
        @intCast(data.len),
        level,
    );

    if (rc != c.Z_OK) {
        return error.CompressFailed;
    }

    // Shrink to actual size
    const result = allocator.realloc(compressed, compressed_len) catch compressed[0..compressed_len];
    return result;
}

/// Decompress data when original size is known
pub fn decompress(data: []const u8, original_size: usize, allocator: std.mem.Allocator) ![]u8 {
    var decompressed = try allocator.alloc(u8, original_size);
    errdefer allocator.free(decompressed);
    var decompressed_len: c.uLongf = @intCast(original_size);

    const rc = c.uncompress(
        decompressed.ptr,
        &decompressed_len,
        data.ptr,
        @intCast(data.len),
    );

    if (rc != c.Z_OK) {
        return error.DecompressFailed;
    }

    return decompressed[0..decompressed_len];
}

/// Decompress data with auto-growing buffer (unknown size)
pub fn decompressAuto(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Start with estimate: uncompressed is usually ~5x compressed
    var buf_size: usize = data.len * 5;
    if (buf_size < 1024) buf_size = 1024;

    while (buf_size <= 256 * 1024 * 1024) { // Max 256MB
        var decompressed = try allocator.alloc(u8, buf_size);
        var decompressed_len: c.uLongf = @intCast(buf_size);

        const rc = c.uncompress(
            decompressed.ptr,
            &decompressed_len,
            data.ptr,
            @intCast(data.len),
        );

        if (rc == c.Z_OK) {
            // Success - shrink to actual size
            const result = allocator.realloc(decompressed, decompressed_len) catch decompressed[0..decompressed_len];
            return result;
        } else if (rc == c.Z_BUF_ERROR) {
            // Buffer too small, try larger
            allocator.free(decompressed);
            buf_size *= 2;
        } else {
            allocator.free(decompressed);
            return error.DecompressFailed;
        }
    }

    return error.BufferTooLarge;
}

/// Compressobj - streaming compression object
pub const CompressObj = struct {
    stream: c.z_stream,
    allocator: std.mem.Allocator,
    initialized: bool,

    pub fn init(level: c_int, method: c_int, wbits: c_int, memlevel: c_int, strategy: c_int, allocator: std.mem.Allocator) !CompressObj {
        _ = method;
        var obj = CompressObj{
            .stream = std.mem.zeroes(c.z_stream),
            .allocator = allocator,
            .initialized = false,
        };

        const rc = c.deflateInit2(
            &obj.stream,
            level,
            c.Z_DEFLATED,
            wbits,
            memlevel,
            strategy,
        );

        if (rc != c.Z_OK) {
            return error.InitFailed;
        }

        obj.initialized = true;
        return obj;
    }

    pub fn deinit(self: *CompressObj) void {
        if (self.initialized) {
            _ = c.deflateEnd(&self.stream);
            self.initialized = false;
        }
    }

    /// Compress a chunk of data
    pub fn compressChunk(self: *CompressObj, data: []const u8, flush_mode: c_int) ![]u8 {
        const bound = c.deflateBound(&self.stream, @intCast(data.len));
        var output = try self.allocator.alloc(u8, bound);
        errdefer self.allocator.free(output);

        self.stream.next_in = @constCast(data.ptr);
        self.stream.avail_in = @intCast(data.len);
        self.stream.next_out = output.ptr;
        self.stream.avail_out = @intCast(bound);

        const rc = c.deflate(&self.stream, flush_mode);
        if (rc != c.Z_OK and rc != c.Z_STREAM_END and rc != c.Z_BUF_ERROR) {
            return error.CompressFailed;
        }

        const produced = bound - self.stream.avail_out;
        return output[0..produced];
    }

    /// Flush all pending output
    pub fn flushOutput(self: *CompressObj, mode: c_int) ![]u8 {
        return self.compressChunk(&[_]u8{}, mode);
    }
};

/// Decompressobj - streaming decompression object
pub const DecompressObj = struct {
    stream: c.z_stream,
    allocator: std.mem.Allocator,
    initialized: bool,
    unconsumed_tail: []u8,
    eof: bool,

    pub fn init(wbits: c_int, allocator: std.mem.Allocator) !DecompressObj {
        var obj = DecompressObj{
            .stream = std.mem.zeroes(c.z_stream),
            .allocator = allocator,
            .initialized = false,
            .unconsumed_tail = &[_]u8{},
            .eof = false,
        };

        const rc = c.inflateInit2(&obj.stream, wbits);

        if (rc != c.Z_OK) {
            return error.InitFailed;
        }

        obj.initialized = true;
        return obj;
    }

    pub fn deinit(self: *DecompressObj) void {
        if (self.initialized) {
            _ = c.inflateEnd(&self.stream);
            self.initialized = false;
        }
        if (self.unconsumed_tail.len > 0) {
            self.allocator.free(self.unconsumed_tail);
        }
    }

    /// Decompress a chunk of data
    pub fn decompressChunk(self: *DecompressObj, data: []const u8, max_length: usize) ![]u8 {
        const output_size = if (max_length > 0) max_length else data.len * 5;
        var output = try self.allocator.alloc(u8, output_size);
        errdefer self.allocator.free(output);

        self.stream.next_in = @constCast(data.ptr);
        self.stream.avail_in = @intCast(data.len);
        self.stream.next_out = output.ptr;
        self.stream.avail_out = @intCast(output_size);

        const rc = c.inflate(&self.stream, c.Z_SYNC_FLUSH);

        if (rc == c.Z_STREAM_END) {
            self.eof = true;
        } else if (rc != c.Z_OK and rc != c.Z_BUF_ERROR) {
            return error.DecompressFailed;
        }

        // Store unconsumed data
        if (self.stream.avail_in > 0) {
            if (self.unconsumed_tail.len > 0) {
                self.allocator.free(self.unconsumed_tail);
            }
            self.unconsumed_tail = try self.allocator.dupe(u8, data[data.len - self.stream.avail_in ..]);
        }

        const produced = output_size - self.stream.avail_out;
        return output[0..produced];
    }

    /// Flush remaining data
    pub fn flushOutput(self: *DecompressObj, length: usize) ![]u8 {
        _ = length;
        return self.decompressChunk(&[_]u8{}, 0);
    }
};

/// Create a compression object (Python compressobj())
pub fn compressobj(level: c_int, method: c_int, wbits: c_int, memlevel: c_int, strategy: c_int, allocator: std.mem.Allocator) !CompressObj {
    return CompressObj.init(level, method, wbits, memlevel, strategy, allocator);
}

/// Create a decompression object (Python decompressobj())
pub fn decompressobj(wbits: c_int, allocator: std.mem.Allocator) !DecompressObj {
    return DecompressObj.init(wbits, allocator);
}

/// Calculate CRC32 checksum
pub fn crc32(data: []const u8, value: u32) u32 {
    return @intCast(c.crc32(@intCast(value), data.ptr, @intCast(data.len)));
}

/// Calculate Adler32 checksum
pub fn adler32(data: []const u8, value: u32) u32 {
    return @intCast(c.adler32(@intCast(value), data.ptr, @intCast(data.len)));
}

/// Get zlib version string
pub fn zlibVersion() []const u8 {
    return std.mem.span(c.zlibVersion());
}

/// Get compile-time version info
pub const ZLIB_VERSION = "1.2.13";
pub const ZLIB_VERNUM = 0x12d0;

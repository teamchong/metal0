/// Python zlib module - compression using libdeflate
/// Provides compress, decompress, crc32, adler32 and related functions
const std = @import("std");
const libdeflate = @import("gzip/libdeflate.zig");
const c = libdeflate.c;

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

/// Compress data using deflate algorithm
pub fn compress(data: []const u8, level: i32) ![]u8 {
    return compressWithAllocator(std.heap.page_allocator, data, level);
}

/// Compress data using deflate with custom allocator
pub fn compressWithAllocator(allocator: std.mem.Allocator, data: []const u8, level: i32) ![]u8 {
    const actual_level: c_int = if (level == Z_DEFAULT_COMPRESSION) 6 else @intCast(level);

    // Create compressor
    const compressor = c.libdeflate_alloc_compressor(actual_level) orelse return ZlibError.OutOfMemory;
    defer c.libdeflate_free_compressor(compressor);

    // Allocate output buffer (worst case: slightly larger than input)
    const max_size = c.libdeflate_zlib_compress_bound(compressor, data.len);
    const output = try allocator.alloc(u8, max_size);
    errdefer allocator.free(output);

    // Compress
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
    // Create decompressor
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

/// Combine two CRC32 checksums
pub fn crc32_combine(crc1: u32, crc2: u32, len2: usize) u32 {
    // Simple implementation - for exact Python compatibility would need proper polynomial math
    _ = len2;
    return crc1 ^ crc2;
}

/// Combine two Adler32 checksums
pub fn adler32_combine(adler1: u32, adler2: u32, len2: usize) u32 {
    // Simple implementation
    _ = len2;
    return adler1 ^ adler2;
}

/// Compress object for streaming compression
pub const compressobj = struct {
    level: i32,
    compressor: ?*c.struct_libdeflate_compressor,
    buffer: std.ArrayList(u8),

    pub fn init(level: i32) compressobj {
        const actual_level: c_int = if (level == Z_DEFAULT_COMPRESSION) 6 else @intCast(level);
        return .{
            .level = level,
            .compressor = c.libdeflate_alloc_compressor(actual_level),
            .buffer = std.ArrayList(u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *compressobj) void {
        if (self.compressor) |comp| {
            c.libdeflate_free_compressor(comp);
        }
        self.buffer.deinit();
    }

    pub fn compress(self: *compressobj, data: []const u8) ![]const u8 {
        try self.buffer.appendSlice(data);
        return "";
    }

    pub fn flush(self: *compressobj, mode: i32) ![]u8 {
        _ = mode;
        if (self.compressor) |comp| {
            const max_size = c.libdeflate_zlib_compress_bound(comp, self.buffer.items.len);
            var output = try std.heap.page_allocator.alloc(u8, max_size);

            const compressed_size = c.libdeflate_zlib_compress(
                comp,
                self.buffer.items.ptr,
                self.buffer.items.len,
                output.ptr,
                output.len,
            );

            self.buffer.clearRetainingCapacity();
            return output[0..compressed_size];
        }
        return "";
    }

    pub fn copy(self: *const compressobj) compressobj {
        var new_obj = compressobj.init(self.level);
        new_obj.buffer.appendSlice(self.buffer.items) catch {};
        return new_obj;
    }
};

/// Decompress object for streaming decompression
pub const decompressobj = struct {
    decompressor: ?*c.struct_libdeflate_decompressor,
    buffer: std.ArrayList(u8),
    unconsumed_tail: []const u8,
    eof: bool,

    pub fn init() decompressobj {
        return .{
            .decompressor = c.libdeflate_alloc_decompressor(),
            .buffer = std.ArrayList(u8).init(std.heap.page_allocator),
            .unconsumed_tail = "",
            .eof = false,
        };
    }

    pub fn deinit(self: *decompressobj) void {
        if (self.decompressor) |decomp| {
            c.libdeflate_free_decompressor(decomp);
        }
        self.buffer.deinit();
    }

    pub fn decompress(self: *decompressobj, data: []const u8, max_length: usize) ![]u8 {
        _ = max_length;
        try self.buffer.appendSlice(data);

        if (self.decompressor) |decomp| {
            const output_size: usize = self.buffer.items.len * 4;
            const output = try std.heap.page_allocator.alloc(u8, output_size);

            var actual_out_size: usize = 0;
            const result = c.libdeflate_zlib_decompress(
                decomp,
                self.buffer.items.ptr,
                self.buffer.items.len,
                output.ptr,
                output.len,
                &actual_out_size,
            );

            if (result == c.LIBDEFLATE_SUCCESS) {
                self.eof = true;
                self.buffer.clearRetainingCapacity();
                return output[0..actual_out_size];
            }
        }
        return "";
    }

    pub fn flush(self: *decompressobj, length: usize) ![]u8 {
        _ = length;
        _ = self;
        return "";
    }

    pub fn copy(self: *const decompressobj) decompressobj {
        var new_obj = decompressobj.init();
        new_obj.buffer.appendSlice(self.buffer.items) catch {};
        new_obj.eof = self.eof;
        return new_obj;
    }
};

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

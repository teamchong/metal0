//! test.test_zipfile.test_compression - ZIP compression tests
//!
//! Tests for various compression methods in ZIP archives including
//! stored, deflate, bzip2, and lzma compression algorithms.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// Compression Method Constants
// ============================================================================

pub const CompressionMethod = enum(u16) {
    stored = 0,
    shrunk = 1,
    reduced_1 = 2,
    reduced_2 = 3,
    reduced_3 = 4,
    reduced_4 = 5,
    imploded = 6,
    deflated = 8,
    enhanced_deflated = 9,
    pkware_dcl = 10,
    bzip2 = 12,
    lzma = 14,
    ibm_terse = 18,
    lz77 = 19,
    zstd = 93,
    mp3 = 94,
    xz = 95,
    jpeg = 96,
    wavpack = 97,
    ppmd = 98,

    pub fn isSupported(self: CompressionMethod) bool {
        return switch (self) {
            .stored, .deflated, .bzip2, .lzma => true,
            else => false,
        };
    }

    pub fn getName(self: CompressionMethod) []const u8 {
        return switch (self) {
            .stored => "stored",
            .shrunk => "shrunk",
            .deflated => "deflated",
            .bzip2 => "bzip2",
            .lzma => "lzma",
            .zstd => "zstd",
            .xz => "xz",
            else => "unknown",
        };
    }
};

// ============================================================================
// Compression Level Configuration
// ============================================================================

pub const CompressionLevel = enum(i32) {
    none = 0,
    fastest = 1,
    fast = 3,
    default = 6,
    best = 9,

    pub fn toZlib(self: CompressionLevel) std.compress.zlib.CompressionLevel {
        return switch (self) {
            .none => .none,
            .fastest, .fast => .fast,
            .default => .default,
            .best => .best,
        };
    }
};

// ============================================================================
// Compressor - Generic compression interface
// ============================================================================

pub const Compressor = struct {
    const Self = @This();

    allocator: mem.Allocator,
    method: CompressionMethod,
    level: CompressionLevel,

    pub const CompressError = error{
        UnsupportedMethod,
        CompressionFailed,
        InvalidInput,
        OutOfMemory,
    };

    pub fn init(allocator: mem.Allocator, method: CompressionMethod) Self {
        return .{
            .allocator = allocator,
            .method = method,
            .level = .default,
        };
    }

    pub fn setLevel(self: *Self, level: CompressionLevel) void {
        self.level = level;
    }

    /// Compress data using configured method
    pub fn compress(self: *Self, data: []const u8) CompressError![]u8 {
        return switch (self.method) {
            .stored => self.compressStored(data),
            .deflated => self.compressDeflate(data),
            else => error.UnsupportedMethod,
        };
    }

    /// Decompress data using configured method
    pub fn decompress(self: *Self, data: []const u8, expected_size: usize) CompressError![]u8 {
        return switch (self.method) {
            .stored => self.decompressStored(data),
            .deflated => self.decompressDeflate(data, expected_size),
            else => error.UnsupportedMethod,
        };
    }

    fn compressStored(self: *Self, data: []const u8) CompressError![]u8 {
        return self.allocator.dupe(u8, data) catch return error.OutOfMemory;
    }

    fn decompressStored(self: *Self, data: []const u8) CompressError![]u8 {
        return self.allocator.dupe(u8, data) catch return error.OutOfMemory;
    }

    fn compressDeflate(self: *Self, data: []const u8) CompressError![]u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        var comp = std.compress.zlib.compressor(output.writer(), .{
            .level = self.level.toZlib(),
        }) catch return error.CompressionFailed;

        comp.writer().writeAll(data) catch return error.CompressionFailed;
        comp.finish() catch return error.CompressionFailed;

        return output.toOwnedSlice() catch return error.OutOfMemory;
    }

    fn decompressDeflate(self: *Self, data: []const u8, expected_size: usize) CompressError![]u8 {
        var fbs = std.io.fixedBufferStream(data);
        var decomp = std.compress.zlib.decompressor(fbs.reader());
        return decomp.reader().readAllAlloc(self.allocator, expected_size) catch return error.CompressionFailed;
    }
};

// ============================================================================
// Compression Statistics
// ============================================================================

pub const CompressionStats = struct {
    original_size: u64,
    compressed_size: u64,
    method: CompressionMethod,
    crc32: u32,

    pub fn ratio(self: CompressionStats) f64 {
        if (self.original_size == 0) return 1.0;
        return @as(f64, @floatFromInt(self.compressed_size)) / @as(f64, @floatFromInt(self.original_size));
    }

    pub fn savings(self: CompressionStats) f64 {
        return 1.0 - self.ratio();
    }

    pub fn savedBytes(self: CompressionStats) i64 {
        return @as(i64, @intCast(self.original_size)) - @as(i64, @intCast(self.compressed_size));
    }
};

// ============================================================================
// Deflate-specific utilities
// ============================================================================

pub const DeflateOptions = struct {
    level: CompressionLevel = .default,
    window_bits: u4 = 15,
    mem_level: u4 = 8,
    strategy: Strategy = .default,

    pub const Strategy = enum {
        default,
        filtered,
        huffman_only,
        rle,
        fixed,
    };
};

pub const DeflateCompressor = struct {
    const Self = @This();

    allocator: mem.Allocator,
    options: DeflateOptions,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .options = .{},
        };
    }

    pub fn initWithOptions(allocator: mem.Allocator, options: DeflateOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        var comp = try std.compress.zlib.compressor(output.writer(), .{
            .level = self.options.level.toZlib(),
        });

        try comp.writer().writeAll(data);
        try comp.finish();

        return output.toOwnedSlice();
    }

    pub fn decompress(self: *Self, data: []const u8, max_size: usize) ![]u8 {
        var fbs = std.io.fixedBufferStream(data);
        var decomp = std.compress.zlib.decompressor(fbs.reader());
        return decomp.reader().readAllAlloc(self.allocator, max_size);
    }
};

// ============================================================================
// Compression Type Detection
// ============================================================================

/// Detect optimal compression method for given data
pub fn detectOptimalMethod(data: []const u8) CompressionMethod {
    if (data.len < 100) return .stored;

    // Check for already compressed data
    if (isCompressedData(data)) return .stored;

    // Check for high entropy (random) data
    const entropy = calculateEntropy(data);
    if (entropy > 7.5) return .stored;

    return .deflated;
}

/// Check if data appears to be already compressed
fn isCompressedData(data: []const u8) bool {
    if (data.len < 4) return false;

    // Check for common compressed file signatures
    const signatures = [_][]const u8{
        &[_]u8{ 0x1f, 0x8b }, // gzip
        &[_]u8{ 0x42, 0x5a }, // bzip2
        &[_]u8{ 0xfd, 0x37, 0x7a, 0x58 }, // xz
        &[_]u8{ 0x50, 0x4b, 0x03, 0x04 }, // ZIP
        &[_]u8{ 0x89, 0x50, 0x4e, 0x47 }, // PNG
        &[_]u8{ 0xff, 0xd8, 0xff }, // JPEG
    };

    for (signatures) |sig| {
        if (data.len >= sig.len and mem.eql(u8, data[0..sig.len], sig)) {
            return true;
        }
    }

    return false;
}

/// Calculate Shannon entropy of data
fn calculateEntropy(data: []const u8) f64 {
    if (data.len == 0) return 0.0;

    var counts: [256]u64 = [_]u64{0} ** 256;
    for (data) |byte| {
        counts[byte] += 1;
    }

    var entropy: f64 = 0.0;
    const len_f = @as(f64, @floatFromInt(data.len));

    for (counts) |count| {
        if (count > 0) {
            const p = @as(f64, @floatFromInt(count)) / len_f;
            entropy -= p * @log2(p);
        }
    }

    return entropy;
}

// ============================================================================
// Tests
// ============================================================================

test "CompressionMethod isSupported" {
    try testing.expect(CompressionMethod.stored.isSupported());
    try testing.expect(CompressionMethod.deflated.isSupported());
    try testing.expect(CompressionMethod.bzip2.isSupported());
    try testing.expect(CompressionMethod.lzma.isSupported());
    try testing.expect(!CompressionMethod.shrunk.isSupported());
}

test "CompressionMethod getName" {
    try testing.expectEqualStrings("stored", CompressionMethod.stored.getName());
    try testing.expectEqualStrings("deflated", CompressionMethod.deflated.getName());
    try testing.expectEqualStrings("bzip2", CompressionMethod.bzip2.getName());
}

test "CompressionLevel toZlib" {
    try testing.expectEqual(std.compress.zlib.CompressionLevel.none, CompressionLevel.none.toZlib());
    try testing.expectEqual(std.compress.zlib.CompressionLevel.fast, CompressionLevel.fastest.toZlib());
    try testing.expectEqual(std.compress.zlib.CompressionLevel.default, CompressionLevel.default.toZlib());
    try testing.expectEqual(std.compress.zlib.CompressionLevel.best, CompressionLevel.best.toZlib());
}

test "Compressor stored compression" {
    var comp = Compressor.init(testing.allocator, .stored);
    const data = "Hello, World!";

    const compressed = try comp.compress(data);
    defer testing.allocator.free(compressed);

    try testing.expectEqualStrings(data, compressed);
}

test "Compressor stored decompression" {
    var comp = Compressor.init(testing.allocator, .stored);
    const data = "Hello, World!";

    const decompressed = try comp.decompress(data, data.len);
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(data, decompressed);
}

test "Compressor deflate roundtrip" {
    var comp = Compressor.init(testing.allocator, .deflated);
    const data = "Hello, World! This is a test of deflate compression.";

    const compressed = try comp.compress(data);
    defer testing.allocator.free(compressed);

    const decompressed = try comp.decompress(compressed, data.len);
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(data, decompressed);
}

test "Compressor unsupported method" {
    var comp = Compressor.init(testing.allocator, .shrunk);
    const result = comp.compress("test");
    try testing.expectError(error.UnsupportedMethod, result);
}

test "CompressionStats ratio" {
    const stats = CompressionStats{
        .original_size = 1000,
        .compressed_size = 500,
        .method = .deflated,
        .crc32 = 0,
    };

    try testing.expectEqual(@as(f64, 0.5), stats.ratio());
    try testing.expectEqual(@as(f64, 0.5), stats.savings());
    try testing.expectEqual(@as(i64, 500), stats.savedBytes());
}

test "CompressionStats zero original size" {
    const stats = CompressionStats{
        .original_size = 0,
        .compressed_size = 0,
        .method = .stored,
        .crc32 = 0,
    };

    try testing.expectEqual(@as(f64, 1.0), stats.ratio());
}

test "DeflateCompressor init" {
    var comp = DeflateCompressor.init(testing.allocator);
    try testing.expectEqual(CompressionLevel.default, comp.options.level);
}

test "DeflateCompressor with options" {
    const options = DeflateOptions{
        .level = .best,
        .window_bits = 12,
    };
    var comp = DeflateCompressor.initWithOptions(testing.allocator, options);
    try testing.expectEqual(CompressionLevel.best, comp.options.level);
}

test "DeflateCompressor roundtrip" {
    var comp = DeflateCompressor.init(testing.allocator);
    const data = "Test data for compression";

    const compressed = try comp.compress(data);
    defer testing.allocator.free(compressed);

    const decompressed = try comp.decompress(compressed, data.len);
    defer testing.allocator.free(decompressed);

    try testing.expectEqualStrings(data, decompressed);
}

test "detectOptimalMethod small data" {
    const small_data = "Hi";
    try testing.expectEqual(CompressionMethod.stored, detectOptimalMethod(small_data));
}

test "detectOptimalMethod normal text" {
    const text = "This is a longer piece of text that should benefit from compression. " ++
        "It contains repeated words and patterns that deflate can handle well.";
    try testing.expectEqual(CompressionMethod.deflated, detectOptimalMethod(text));
}

test "isCompressedData gzip" {
    const gzip_header = [_]u8{ 0x1f, 0x8b, 0x08, 0x00 };
    try testing.expect(isCompressedData(&gzip_header));
}

test "isCompressedData plain text" {
    const text = "This is plain text";
    try testing.expect(!isCompressedData(text));
}

test "calculateEntropy zero" {
    const empty = "";
    try testing.expectEqual(@as(f64, 0.0), calculateEntropy(empty));
}

test "calculateEntropy uniform" {
    // All same byte - zero entropy
    var same: [100]u8 = undefined;
    @memset(&same, 'A');
    const entropy = calculateEntropy(&same);
    try testing.expectEqual(@as(f64, 0.0), entropy);
}

test "calculateEntropy mixed" {
    const mixed = "AABBCCDD";
    const entropy = calculateEntropy(mixed);
    try testing.expect(entropy > 0.0);
    try testing.expect(entropy < 8.0);
}

test "compression method enum values" {
    try testing.expectEqual(@as(u16, 0), @intFromEnum(CompressionMethod.stored));
    try testing.expectEqual(@as(u16, 8), @intFromEnum(CompressionMethod.deflated));
    try testing.expectEqual(@as(u16, 12), @intFromEnum(CompressionMethod.bzip2));
    try testing.expectEqual(@as(u16, 14), @intFromEnum(CompressionMethod.lzma));
}

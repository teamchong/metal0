//! CPython source: Lib/encodings/zlib_codec.py
//!
//! Implements zlib/deflate compression encoding.
//! Uses Zig's built-in std.compress.zlib.
//!
//! Mirrors: CPython Lib/encodings/zlib_codec.py

const std = @import("std");

pub const name = "zlib";
pub const aliases = [_][]const u8{ "zlib_codec", "zip", "deflate" };

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

pub const ErrorMode = enum {
    strict,
    replace,
    ignore,
    xmlcharrefreplace,
    backslashreplace,
};

/// Decode (decompress) zlib data
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = mode;

    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var fbs = std.io.fixedBufferStream(input);
    var decomp = std.compress.zlib.decompressor(fbs.reader());

    // Read in chunks
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = decomp.reader().read(&buf) catch |err| {
            return switch (err) {
                error.EndOfStream => break,
                else => error.DecompressionError,
            };
        };
        if (n == 0) break;
        try result.appendSlice(allocator, buf[0..n]);
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode (compress) data with zlib
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;

    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var comp = std.compress.zlib.compressor(.{}, result.writer()) catch return error.CompressionError;

    _ = comp.write(input) catch return error.CompressionError;
    comp.finish() catch return error.CompressionError;

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "zlib roundtrip" {
    const original = "Hello, World! This is a test of zlib compression.";
    const encoded = try encode(std.testing.allocator, original, .strict);
    defer std.testing.allocator.free(encoded.output);

    // Compressed should be smaller for repeated content
    try std.testing.expect(encoded.output.len > 0);

    const decoded = try decode(std.testing.allocator, encoded.output, .strict);
    defer std.testing.allocator.free(decoded.output);

    try std.testing.expectEqualStrings(original, decoded.output);
}

test "zlib encode produces valid data" {
    const input = "Test data for compression";
    const result = try encode(std.testing.allocator, input, .strict);
    defer std.testing.allocator.free(result.output);

    // zlib header starts with 0x78 (CMF)
    try std.testing.expect(result.output.len >= 2);
    try std.testing.expect(result.output[0] == 0x78);
}

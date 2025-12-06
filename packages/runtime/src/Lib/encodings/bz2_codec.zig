//! Python 'bz2' Codec
//!
//! Implements bzip2 compression encoding.
//! Note: Zig std doesn't have bz2, so this is a stub that returns errors.
//!
//! Mirrors: CPython Lib/encodings/bz2_codec.py

const std = @import("std");

pub const name = "bz2";
pub const aliases = [_][]const u8{ "bz2_codec", "bzip2" };

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

/// Decode (decompress) bz2 data
/// Note: Currently not implemented - Zig std library doesn't include bz2
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = allocator;
    _ = input;
    _ = mode;
    // bz2 compression requires external library or C binding
    // For now, return error indicating this codec needs external support
    return error.Bz2NotSupported;
}

/// Encode (compress) data with bz2
/// Note: Currently not implemented - Zig std library doesn't include bz2
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = allocator;
    _ = input;
    _ = mode;
    // bz2 compression requires external library or C binding
    // For now, return error indicating this codec needs external support
    return error.Bz2NotSupported;
}

test "bz2 codec not supported" {
    const decode_result = decode(std.testing.allocator, "test", .strict);
    try std.testing.expectError(error.Bz2NotSupported, decode_result);

    const encode_result = encode(std.testing.allocator, "test", .strict);
    try std.testing.expectError(error.Bz2NotSupported, encode_result);
}

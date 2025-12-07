//! CPython source: Lib/encodings/_win_cp_codecs.py
//!
//! Provides Windows-specific code page codec infrastructure.
//! On non-Windows platforms, provides fallback implementations.
//!
//! Mirrors: CPython Lib/encodings/cp*.py (Windows-specific behavior)

const std = @import("std");

pub const name = "_win_cp_codecs";
pub const aliases = [_][]const u8{};

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

/// Get a codec for a Windows code page number
/// Returns null if the code page is not supported
pub fn getCodec(code_page: u32) ?*const CodecFns {
    return switch (code_page) {
        437 => &cp437_fns,
        850 => &cp850_fns,
        1252 => &cp1252_fns,
        65001 => &utf8_fns, // UTF-8 code page
        else => null,
    };
}

pub const CodecFns = struct {
    decode: *const fn (std.mem.Allocator, []const u8, ErrorMode) anyerror!DecodeResult,
    encode: *const fn (std.mem.Allocator, []const u8, ErrorMode) anyerror!EncodeResult,
};

// Import the actual codec implementations
const cp437 = @import("cp437.zig");
const cp850 = @import("cp850.zig");
const cp1252 = @import("cp1252.zig");
const utf_8 = @import("utf_8.zig");

const cp437_fns = CodecFns{
    .decode = &cp437.decode,
    .encode = &cp437.encode,
};

const cp850_fns = CodecFns{
    .decode = &cp850.decode,
    .encode = &cp850.encode,
};

const cp1252_fns = CodecFns{
    .decode = &cp1252.decode,
    .encode = &cp1252.encode,
};

const utf8_fns = CodecFns{
    .decode = &utf_8.decode,
    .encode = &utf_8.encode,
};

/// Decode using a specific Windows code page
pub fn decode(allocator: std.mem.Allocator, input: []const u8, code_page: u32, mode: ErrorMode) !DecodeResult {
    const codec = getCodec(code_page) orelse return error.UnsupportedCodePage;
    return codec.decode(allocator, input, mode);
}

/// Encode using a specific Windows code page
pub fn encode(allocator: std.mem.Allocator, input: []const u8, code_page: u32, mode: ErrorMode) !EncodeResult {
    const codec = getCodec(code_page) orelse return error.UnsupportedCodePage;
    return codec.encode(allocator, input, mode);
}

test "win_cp decode cp437" {
    const result = try decode(std.testing.allocator, "Hello", 437, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "win_cp decode utf8" {
    const result = try decode(std.testing.allocator, "Hello", 65001, .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "win_cp unsupported" {
    const result = decode(std.testing.allocator, "test", 99999, .strict);
    try std.testing.expectError(error.UnsupportedCodePage, result);
}

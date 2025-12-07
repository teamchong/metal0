//! CPython source: Lib/encodings/undefined.py
//!
//! This codec will always raise a UnicodeError exception when being used.
//! It is intended for use by the site.py file to switch off automatic
//! string to Unicode coercion.
//!
//! Mirrors: CPython Lib/encodings/undefined.py

const std = @import("std");

pub const name = "undefined";
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

/// Always raises UnicodeError - this codec is intentionally undefined
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    _ = allocator;
    _ = input;
    _ = mode;
    return error.UndefinedEncoding;
}

/// Always raises UnicodeError - this codec is intentionally undefined
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = allocator;
    _ = input;
    _ = mode;
    return error.UndefinedEncoding;
}

test "undefined codec always errors" {
    const result = decode(std.testing.allocator, "test", .strict);
    try std.testing.expectError(error.UndefinedEncoding, result);

    const encode_result = encode(std.testing.allocator, "test", .strict);
    try std.testing.expectError(error.UndefinedEncoding, encode_result);
}

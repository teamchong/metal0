//! CPython source: Lib/encodings/utf_8_sig.py
//!
//! UTF-8 with BOM signature. Strips BOM on decode, adds BOM on encode.
//!
//! Mirrors: CPython Lib/encodings/utf_8_sig.py

const std = @import("std");
const charmap = @import("charmap.zig");
const utf_8 = @import("utf_8.zig");

pub const name = "utf-8-sig";
pub const aliases = [_][]const u8{ "utf_8_sig", "UTF-8-SIG" };

pub const ErrorHandler = charmap.ErrorHandler;
pub const DecodeResult = charmap.DecodeResult;
pub const EncodeResult = charmap.EncodeResult;

/// UTF-8 BOM
pub const BOM = "\xef\xbb\xbf";

/// Decode UTF-8 bytes, stripping BOM if present
pub fn decode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !DecodeResult {
    return utf_8.decodeWithBom(allocator, input, errors);
}

/// Encode UTF-8 string with BOM prefix
pub fn encode(allocator: std.mem.Allocator, input: []const u8, errors: ErrorHandler) !EncodeResult {
    const inner_result = try utf_8.encode(allocator, input, errors);

    // Prepend BOM
    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    try output.appendSlice(allocator, BOM);
    try output.appendSlice(allocator, inner_result.output);
    allocator.free(inner_result.output);

    return .{
        .output = try output.toOwnedSlice(allocator),
        .chars_consumed = inner_result.chars_consumed,
    };
}

test "utf8sig decode strips bom" {
    const result = try decode(std.testing.allocator, "\xef\xbb\xbfHello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "utf8sig encode adds bom" {
    const result = try encode(std.testing.allocator, "Hi", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("\xef\xbb\xbfHi", result.output);
}

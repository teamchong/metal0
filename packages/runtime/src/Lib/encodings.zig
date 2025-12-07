//! Python 'encodings' module - Standard Encodings Package
//!
//! This package contains the standard Python codecs.
//!
//! Mirrors: CPython Lib/encodings/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const EncodingError = error{
    UnknownEncoding,
    EncodeError,
    DecodeError,
    InvalidCodePoint,
    OutOfMemory,
};

// ============================================================================
// CodecInfo
// ============================================================================

/// Information about a codec
pub const CodecInfo = struct {
    name: []const u8,
    encode: ?*const fn ([]const u8, []const u8) anyerror![]u8 = null,
    decode: ?*const fn ([]const u8, []const u8) anyerror![]u8 = null,
    incrementalencoder: ?*anyopaque = null,
    incrementaldecoder: ?*anyopaque = null,
    streamreader: ?*anyopaque = null,
    streamwriter: ?*anyopaque = null,
};

// ============================================================================
// Codec Registry
// ============================================================================

/// Normalize encoding name
pub fn normalize_encoding(allocator: std.mem.Allocator, encoding: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    for (encoding) |c| {
        if (c == ' ' or c == '-' or c == '_') {
            // Skip or normalize to underscore
            continue;
        } else {
            try result.append(std.ascii.toLower(c));
        }
    }

    return result.toOwnedSlice();
}

/// Search for a codec
pub fn search_function(encoding: []const u8) ?CodecInfo {
    // Normalize the encoding name
    const normalized = blk: {
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        for (encoding) |c| {
            if (c != ' ' and c != '-' and c != '_' and len < buf.len) {
                buf[len] = std.ascii.toLower(c);
                len += 1;
            }
        }
        break :blk buf[0..len];
    };

    // Standard encodings
    const encodings = std.StaticStringMap(CodecInfo).initComptime(.{
        .{ "utf8", CodecInfo{ .name = "utf-8" } },
        .{ "utf_8", CodecInfo{ .name = "utf-8" } },
        .{ "ascii", CodecInfo{ .name = "ascii" } },
        .{ "latin1", CodecInfo{ .name = "latin-1" } },
        .{ "latin_1", CodecInfo{ .name = "latin-1" } },
        .{ "iso88591", CodecInfo{ .name = "iso-8859-1" } },
        .{ "utf16", CodecInfo{ .name = "utf-16" } },
        .{ "utf_16", CodecInfo{ .name = "utf-16" } },
        .{ "utf16le", CodecInfo{ .name = "utf-16-le" } },
        .{ "utf16be", CodecInfo{ .name = "utf-16-be" } },
        .{ "utf32", CodecInfo{ .name = "utf-32" } },
        .{ "utf_32", CodecInfo{ .name = "utf-32" } },
        .{ "cp1252", CodecInfo{ .name = "cp1252" } },
        .{ "cp437", CodecInfo{ .name = "cp437" } },
    });

    return encodings.get(normalized);
}

// ============================================================================
// Aliases
// ============================================================================

/// Get canonical encoding name
pub fn getCanonicalName(encoding: []const u8) []const u8 {
    const info = search_function(encoding);
    if (info) |i| {
        return i.name;
    }
    return encoding;
}

/// Standard encoding aliases
pub const aliases = struct {
    pub const utf8 = &[_][]const u8{ "utf-8", "utf8", "utf_8", "U8", "UTF" };
    pub const ascii = &[_][]const u8{ "ascii", "646", "us-ascii" };
    pub const latin1 = &[_][]const u8{ "latin-1", "latin1", "iso-8859-1", "iso8859-1", "8859" };
    pub const utf16 = &[_][]const u8{ "utf-16", "utf16", "utf_16" };
    pub const utf32 = &[_][]const u8{ "utf-32", "utf32", "utf_32" };
};

// ============================================================================
// Codec Functions
// ============================================================================

/// Encode string to bytes
pub fn encode(allocator: std.mem.Allocator, input: []const u8, encoding: []const u8, errors: []const u8) ![]u8 {
    _ = errors;

    const info = search_function(encoding) orelse return error.UnknownEncoding;

    // For UTF-8, just copy
    if (std.mem.eql(u8, info.name, "utf-8")) {
        return allocator.dupe(u8, input);
    }

    // For ASCII, validate and copy
    if (std.mem.eql(u8, info.name, "ascii")) {
        for (input) |c| {
            if (c > 127) return error.EncodeError;
        }
        return allocator.dupe(u8, input);
    }

    // For Latin-1, just copy (all bytes valid)
    if (std.mem.eql(u8, info.name, "latin-1")) {
        return allocator.dupe(u8, input);
    }

    return error.UnknownEncoding;
}

/// Decode bytes to string
pub fn decode(allocator: std.mem.Allocator, input: []const u8, encoding: []const u8, errors: []const u8) ![]u8 {
    _ = errors;

    const info = search_function(encoding) orelse return error.UnknownEncoding;

    // For UTF-8, validate and copy
    if (std.mem.eql(u8, info.name, "utf-8")) {
        if (!std.unicode.utf8ValidateSlice(input)) {
            return error.DecodeError;
        }
        return allocator.dupe(u8, input);
    }

    // For ASCII, validate and copy
    if (std.mem.eql(u8, info.name, "ascii")) {
        for (input) |c| {
            if (c > 127) return error.DecodeError;
        }
        return allocator.dupe(u8, input);
    }

    // For Latin-1, convert to UTF-8
    if (std.mem.eql(u8, info.name, "latin-1")) {
        var result = std.ArrayList(u8).init(allocator);
        for (input) |c| {
            if (c < 128) {
                try result.append(c);
            } else {
                // Encode as UTF-8
                try result.append(0xC0 | (c >> 6));
                try result.append(0x80 | (c & 0x3F));
            }
        }
        return result.toOwnedSlice();
    }

    return error.UnknownEncoding;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "normalize_encoding" {
    const allocator = std.testing.allocator;

    const n1 = try normalize_encoding(allocator, "UTF-8");
    defer allocator.free(n1);
    try std.testing.expectEqualStrings("utf8", n1);

    const n2 = try normalize_encoding(allocator, "ISO_8859_1");
    defer allocator.free(n2);
    try std.testing.expectEqualStrings("iso88591", n2);
}

test "search_function" {
    const info = search_function("utf-8");
    try std.testing.expect(info != null);
    try std.testing.expectEqualStrings("utf-8", info.?.name);
}

test "search_function unknown" {
    const info = search_function("unknown-encoding-xyz");
    try std.testing.expect(info == null);
}

test "encode utf8" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "hello", "utf-8", "strict");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "encode ascii" {
    const allocator = std.testing.allocator;
    const result = try encode(allocator, "hello", "ascii", "strict");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "decode utf8" {
    const allocator = std.testing.allocator;
    const result = try decode(allocator, "hello", "utf-8", "strict");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "getCanonicalName" {
    try std.testing.expectEqualStrings("utf-8", getCanonicalName("UTF-8"));
    try std.testing.expectEqualStrings("ascii", getCanonicalName("ASCII"));
}

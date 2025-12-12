//! CPython source: Lib/nturl2path.py
//!
//! Provides functions for converting between Windows file paths and URLs.
//! Handles file:// URL encoding/decoding for Windows paths.
//!
//! Mirrors: CPython Lib/nturl2path.py

const std = @import("std");

// ============================================================================
// url2pathname - Convert URL to Windows path
// ============================================================================

/// Convert a file: URL to a Windows path.
/// Handles:
///   file:///C:/path -> C:\path
///   file://server/share/path -> \\server\share\path
///   file:///C|/path -> C:\path (legacy IE format)
pub fn url2pathname(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    // Remove leading slashes
    var path = url;
    while (path.len > 0 and path[0] == '/') {
        path = path[1..];
    }

    // Handle UNC paths (//server/share -> \\server\share)
    if (url.len >= 2 and url[0] == '/' and url[1] == '/') {
        try result.appendSlice(allocator, "\\\\");
        path = url[2..];
    }

    // Decode URL-encoded characters and convert slashes
    var i: usize = 0;
    while (i < path.len) {
        const c = path[i];
        if (c == '%' and i + 2 < path.len) {
            // URL-encoded character
            const hex = path[i + 1 .. i + 3];
            if (hexToInt(hex)) |value| {
                try result.append(allocator, value);
                i += 3;
                continue;
            }
        }

        if (c == '/') {
            try result.append(allocator, '\\');
        } else if (c == '|' and i == 1) {
            // Legacy IE format: C| -> C:
            try result.append(allocator, ':');
        } else {
            try result.append(allocator, c);
        }
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// pathname2url - Convert Windows path to URL
// ============================================================================

/// Convert a Windows path to a file: URL.
/// Handles:
///   C:\path -> file:///C:/path
///   \\server\share\path -> file://server/share/path
pub fn pathname2url(allocator: std.mem.Allocator, pathname: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var path = pathname;

    // Handle UNC paths
    if (path.len >= 2 and path[0] == '\\' and path[1] == '\\') {
        try result.appendSlice(allocator, "//");
        path = path[2..];
    } else {
        try result.append(allocator, '/');
    }

    // Encode special characters and convert backslashes
    for (path) |c| {
        if (c == '\\') {
            try result.append(allocator, '/');
        } else if (needsEncoding(c)) {
            try result.append(allocator, '%');
            try result.append(allocator, HEX_DIGITS[c >> 4]);
            try result.append(allocator, HEX_DIGITS[c & 0x0F]);
        } else {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Helper functions
// ============================================================================

const HEX_DIGITS = "0123456789ABCDEF";

/// Check if character needs URL encoding
fn needsEncoding(c: u8) bool {
    // RFC 3986 unreserved characters don't need encoding
    // unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
    // Plus we allow : and @ for paths
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9' => false,
        '-', '.', '_', '~', ':', '@', '/' => false,
        else => true,
    };
}

/// Convert a 2-character hex string to a byte value
fn hexToInt(hex: []const u8) ?u8 {
    if (hex.len != 2) return null;

    const high = hexDigitToInt(hex[0]) orelse return null;
    const low = hexDigitToInt(hex[1]) orelse return null;

    return (high << 4) | low;
}

/// Convert a single hex digit to its integer value
fn hexDigitToInt(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'A'...'F' => @intCast(c - 'A' + 10),
        'a'...'f' => @intCast(c - 'a' + 10),
        else => null,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "url2pathname simple" {
    const allocator = std.testing.allocator;
    const result = try url2pathname(allocator, "/C:/Users/test");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\Users\\test", result);
}

test "url2pathname with encoded space" {
    const allocator = std.testing.allocator;
    const result = try url2pathname(allocator, "/C:/My%20Documents");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\My Documents", result);
}

test "url2pathname UNC path" {
    const allocator = std.testing.allocator;
    const result = try url2pathname(allocator, "//server/share/path");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("\\\\server\\share\\path", result);
}

test "url2pathname legacy pipe format" {
    const allocator = std.testing.allocator;
    const result = try url2pathname(allocator, "/C|/path");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("C:\\path", result);
}

test "pathname2url simple" {
    const allocator = std.testing.allocator;
    const result = try pathname2url(allocator, "C:\\Users\\test");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/C:/Users/test", result);
}

test "pathname2url with space" {
    const allocator = std.testing.allocator;
    const result = try pathname2url(allocator, "C:\\My Documents");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/C:/My%20Documents", result);
}

test "pathname2url UNC path" {
    const allocator = std.testing.allocator;
    const result = try pathname2url(allocator, "\\\\server\\share\\path");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("//server/share/path", result);
}

test "hexToInt" {
    try std.testing.expectEqual(@as(?u8, 0x20), hexToInt("20"));
    try std.testing.expectEqual(@as(?u8, 0xFF), hexToInt("FF"));
    try std.testing.expectEqual(@as(?u8, 0xff), hexToInt("ff"));
    try std.testing.expectEqual(@as(?u8, 0x0A), hexToInt("0A"));
    try std.testing.expectEqual(@as(?u8, null), hexToInt("GG"));
}

test "needsEncoding" {
    try std.testing.expect(!needsEncoding('A'));
    try std.testing.expect(!needsEncoding('z'));
    try std.testing.expect(!needsEncoding('0'));
    try std.testing.expect(!needsEncoding('-'));
    try std.testing.expect(!needsEncoding('/'));
    try std.testing.expect(needsEncoding(' '));
    try std.testing.expect(needsEncoding('%'));
    try std.testing.expect(needsEncoding('#'));
}

test "roundtrip" {
    const allocator = std.testing.allocator;
    const original = "C:\\Users\\test\\file.txt";

    const url = try pathname2url(allocator, original);
    defer allocator.free(url);

    const restored = try url2pathname(allocator, url);
    defer allocator.free(restored);

    try std.testing.expectEqualStrings(original, restored);
}

//! Python 'urllib' module - URL handling utilities
//!
//! Provides URL parsing, encoding, and request handling.
//!
//! Mirrors: CPython Lib/urllib/

const std = @import("std");

// Re-export submodules
pub const parse = @import("urllib/parse.zig");
pub const request = @import("urllib/request.zig");
pub const error_mod = @import("urllib/error.zig");
pub const response = @import("urllib/response.zig");
pub const robotparser = @import("urllib/robotparser.zig");

// Re-export Error for compatibility
pub const Error = error_mod.Error;

// ============================================================================
// Tests
// ============================================================================

test "urlparse basic" {
    const result = parse.urlparse("https://www.example.com/path?query=value#fragment");

    try std.testing.expectEqualStrings("https", result.scheme);
    try std.testing.expectEqualStrings("www.example.com", result.netloc);
    try std.testing.expectEqualStrings("/path", result.path);
    try std.testing.expectEqualStrings("query=value", result.query);
    try std.testing.expectEqualStrings("fragment", result.fragment);
}

test "urlparse with port" {
    const result = parse.urlparse("http://localhost:8080/api/v1");

    try std.testing.expectEqualStrings("http", result.scheme);
    try std.testing.expectEqualStrings("localhost:8080", result.netloc);
    try std.testing.expectEqualStrings("/api/v1", result.path);
    try std.testing.expectEqual(@as(?u16, 8080), result.port());
    try std.testing.expectEqualStrings("localhost", result.hostname().?);
}

test "quote" {
    const allocator = std.testing.allocator;

    const result = try parse.quote(allocator, "hello world", "");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello%20world", result);
}

test "quote_plus" {
    const allocator = std.testing.allocator;

    const result = try parse.quote_plus(allocator, "hello world", "");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello+world", result);
}

test "unquote" {
    const allocator = std.testing.allocator;

    const result = try parse.unquote(allocator, "hello%20world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "unquote_plus" {
    const allocator = std.testing.allocator;

    const result = try parse.unquote_plus(allocator, "hello+world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello world", result);
}

test "urlunparse" {
    const allocator = std.testing.allocator;

    const components = parse.ParseResult{
        .scheme = "https",
        .netloc = "example.com",
        .path = "/path",
        .params = "",
        .query = "key=value",
        .fragment = "section",
    };

    const result = try parse.urlunparse(allocator, components);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("https://example.com/path?key=value#section", result);
}

test "urlencode" {
    const allocator = std.testing.allocator;

    const params = [_]struct { key: []const u8, value: []const u8 }{
        .{ .key = "name", .value = "John Doe" },
        .{ .key = "age", .value = "30" },
    };

    const result = try parse.urlencode(allocator, &params);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("name=John+Doe&age=30", result);
}

test "hostname extraction" {
    const result = parse.urlparse("https://user:pass@example.com:8080/path");

    try std.testing.expectEqualStrings("example.com", result.hostname().?);
    try std.testing.expectEqual(@as(?u16, 8080), result.port());
    try std.testing.expectEqualStrings("user", result.username().?);
    try std.testing.expectEqualStrings("pass", result.password().?);
}

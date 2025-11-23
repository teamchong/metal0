/// Fast HTTP header parser with SIMD optimization
const std = @import("std");
const Headers = @import("../request.zig").Headers;

/// Parse HTTP headers from raw bytes
pub fn parseHeaders(allocator: std.mem.Allocator, data: []const u8) !Headers {
    var headers = Headers.init(allocator);
    errdefer headers.deinit();

    var lines = std.mem.splitSequence(u8, data, "\r\n");

    // Skip first line (request/response line)
    _ = lines.next();

    while (lines.next()) |line| {
        if (line.len == 0) break; // End of headers

        const colon_pos = findColon(line) orelse continue;
        const key = std.mem.trim(u8, line[0..colon_pos], " \t");
        const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");

        try headers.set(key, value);
    }

    return headers;
}

/// Find colon position in header line (can be optimized with SIMD)
inline fn findColon(line: []const u8) ?usize {
    return std.mem.indexOf(u8, line, ":");
}

/// SIMD-optimized header parsing for common cases
pub fn parseHeadersFast(allocator: std.mem.Allocator, data: []const u8) !Headers {
    // For now, use regular parsing
    // TODO: Implement SIMD version using @Vector when stable
    return parseHeaders(allocator, data);
}

/// Parse Content-Length header quickly
pub fn parseContentLength(headers: *const Headers) !usize {
    const len_str = headers.get("Content-Length") orelse return 0;
    return try std.fmt.parseInt(usize, len_str, 10);
}

/// Check if connection should be kept alive
pub fn isKeepAlive(headers: *const Headers, version: []const u8) bool {
    if (headers.get("Connection")) |conn| {
        if (std.mem.eql(u8, conn, "keep-alive")) return true;
        if (std.mem.eql(u8, conn, "close")) return false;
    }

    // HTTP/1.1 defaults to keep-alive
    return std.mem.eql(u8, version, "HTTP/1.1");
}

/// Parse Transfer-Encoding header
pub fn isChunked(headers: *const Headers) bool {
    if (headers.get("Transfer-Encoding")) |encoding| {
        return std.mem.indexOf(u8, encoding, "chunked") != null;
    }
    return false;
}

/// Extract hostname from Host header
pub fn getHost(headers: *const Headers) ?[]const u8 {
    return headers.get("Host");
}

/// Extract Content-Type
pub fn getContentType(headers: *const Headers) ?[]const u8 {
    return headers.get("Content-Type");
}

/// Check if Content-Type is JSON
pub fn isJson(headers: *const Headers) bool {
    if (getContentType(headers)) |ct| {
        return std.mem.indexOf(u8, ct, "application/json") != null;
    }
    return false;
}

/// Check if Content-Type is form data
pub fn isFormData(headers: *const Headers) bool {
    if (getContentType(headers)) |ct| {
        return std.mem.indexOf(u8, ct, "application/x-www-form-urlencoded") != null;
    }
    return false;
}

/// Parse cookie header into key-value pairs
pub fn parseCookies(allocator: std.mem.Allocator, headers: *const Headers) !std.StringHashMap([]const u8) {
    var cookies = std.StringHashMap([]const u8).init(allocator);
    errdefer cookies.deinit();

    const cookie_header = headers.get("Cookie") orelse return cookies;

    var pairs = std.mem.splitSequence(u8, cookie_header, "; ");
    while (pairs.next()) |pair| {
        const eq_pos = std.mem.indexOf(u8, pair, "=") orelse continue;
        const key = pair[0..eq_pos];
        const value = pair[eq_pos + 1 ..];

        const key_copy = try allocator.dupe(u8, key);
        errdefer allocator.free(key_copy);
        const value_copy = try allocator.dupe(u8, value);
        errdefer allocator.free(value_copy);

        try cookies.put(key_copy, value_copy);
    }

    return cookies;
}

test "parseHeaders basic" {
    const allocator = std.testing.allocator;

    const raw =
        \\GET /api HTTP/1.1
        \\Host: example.com
        \\User-Agent: PyAOT/1.0
        \\Content-Type: application/json
        \\
        \\
    ;

    var headers = try parseHeaders(allocator, raw);
    defer headers.deinit();

    try std.testing.expectEqualStrings("example.com", headers.get("Host").?);
    try std.testing.expectEqualStrings("PyAOT/1.0", headers.get("User-Agent").?);
    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "parseContentLength" {
    const allocator = std.testing.allocator;

    var headers = Headers.init(allocator);
    defer headers.deinit();

    try headers.set("Content-Length", "1234");

    const length = try parseContentLength(&headers);
    try std.testing.expectEqual(@as(usize, 1234), length);
}

test "isKeepAlive" {
    const allocator = std.testing.allocator;

    var headers = Headers.init(allocator);
    defer headers.deinit();

    // HTTP/1.1 defaults to keep-alive
    try std.testing.expect(isKeepAlive(&headers, "HTTP/1.1"));

    try headers.set("Connection", "close");
    try std.testing.expect(!isKeepAlive(&headers, "HTTP/1.1"));

    try headers.set("Connection", "keep-alive");
    try std.testing.expect(isKeepAlive(&headers, "HTTP/1.1"));
}

test "isJson" {
    const allocator = std.testing.allocator;

    var headers = Headers.init(allocator);
    defer headers.deinit();

    try std.testing.expect(!isJson(&headers));

    try headers.set("Content-Type", "application/json");
    try std.testing.expect(isJson(&headers));

    try headers.set("Content-Type", "application/json; charset=utf-8");
    try std.testing.expect(isJson(&headers));
}

test "parseCookies" {
    const allocator = std.testing.allocator;

    var headers = Headers.init(allocator);
    defer headers.deinit();

    try headers.set("Cookie", "session=abc123; user=john");

    var cookies = try parseCookies(allocator, &headers);
    defer {
        var it = cookies.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        cookies.deinit();
    }

    try std.testing.expectEqualStrings("abc123", cookies.get("session").?);
    try std.testing.expectEqualStrings("john", cookies.get("user").?);
}

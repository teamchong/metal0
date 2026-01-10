//! http.cookies - HTTP cookie handling
//! Reference: cpython/Lib/http/cookies.py
//!
//! CPython __all__: CookieError, BaseCookie, SimpleCookie
//!
//! HTTP state management mechanism (cookies) per RFC 6265.

const std = @import("std");

/// Cookie parsing/generation error
pub const CookieError = error{
    InvalidCookie,
    InvalidAttribute,
    InvalidValue,
};

/// Cookie attributes
pub const Morsel = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
    coded_value: []const u8,

    // Cookie attributes
    expires: ?[]const u8 = null,
    path: ?[]const u8 = null,
    domain: ?[]const u8 = null,
    max_age: ?i64 = null,
    secure: bool = false,
    httponly: bool = false,
    samesite: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, key: []const u8, value: []const u8) Self {
        return .{
            .allocator = allocator,
            .key = key,
            .value = value,
            .coded_value = value,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // Free owned strings if we allocated them
    }

    /// Output cookie as string for Set-Cookie header
    pub fn outputString(self: *Self, allocator: std.mem.Allocator, attrs: ?[]const []const u8) ![]const u8 {
        _ = attrs;

        var output: std.ArrayList(u8) = .{};
        errdefer output.deinit(allocator);

        // Key=Value
        try output.appendSlice(allocator, self.key);
        try output.append(allocator, '=');
        try output.appendSlice(allocator, self.coded_value);

        // Attributes
        if (self.expires) |expires| {
            try output.appendSlice(allocator, "; Expires=");
            try output.appendSlice(allocator, expires);
        }

        if (self.path) |path| {
            try output.appendSlice(allocator, "; Path=");
            try output.appendSlice(allocator, path);
        }

        if (self.domain) |domain| {
            try output.appendSlice(allocator, "; Domain=");
            try output.appendSlice(allocator, domain);
        }

        if (self.max_age) |max_age| {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "; Max-Age={d}", .{max_age}) catch unreachable;
            try output.appendSlice(allocator, str);
        }

        if (self.secure) {
            try output.appendSlice(allocator, "; Secure");
        }

        if (self.httponly) {
            try output.appendSlice(allocator, "; HttpOnly");
        }

        if (self.samesite) |samesite| {
            try output.appendSlice(allocator, "; SameSite=");
            try output.appendSlice(allocator, samesite);
        }

        return output.toOwnedSlice(allocator);
    }
};

/// Base cookie class
pub const BaseCookie = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cookies: std.StringHashMap(Morsel),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cookies = std.StringHashMap(Morsel).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.cookies.valueIterator();
        while (iter.next()) |morsel| {
            morsel.deinit();
        }
        self.cookies.deinit();
    }

    /// Set a cookie value
    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        try self.cookies.put(key, Morsel.init(self.allocator, key, value));
    }

    /// Get a cookie morsel
    pub fn get(self: *Self, key: []const u8) ?*Morsel {
        return self.cookies.getPtr(key);
    }

    /// Check if cookie exists
    pub fn contains(self: *Self, key: []const u8) bool {
        return self.cookies.contains(key);
    }

    /// Remove a cookie
    pub fn remove(self: *Self, key: []const u8) void {
        if (self.cookies.fetchRemove(key)) |kv| {
            var morsel = kv.value;
            morsel.deinit();
        }
    }

    /// Parse a Cookie header
    pub fn load(self: *Self, header: []const u8) !void {
        var iter = std.mem.splitSequence(u8, header, "; ");
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
                const key = trimmed[0..eq];
                const value = trimmed[eq + 1 ..];
                try self.set(key, value);
            }
        }
    }

    /// Output all cookies for Set-Cookie headers
    pub fn output(self: *Self, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result: std.ArrayList([]const u8) = .{};
        errdefer result.deinit(allocator);

        var iter = self.cookies.valueIterator();
        while (iter.next()) |morsel| {
            const str = try morsel.outputString(allocator, null);
            try result.append(allocator, str);
        }

        return result;
    }
};

/// Simple cookie (the most commonly used)
pub const SimpleCookie = BaseCookie;

/// Quote a string for cookie value
pub fn quote(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    // Check if quoting is needed
    var needs_quoting = false;
    for (value) |c| {
        if (c == '"' or c == '\\' or c == ',' or c == ';' or c < 0x20 or c > 0x7E) {
            needs_quoting = true;
            break;
        }
    }

    if (!needs_quoting) {
        return try allocator.dupe(u8, value);
    }

    var output: std.ArrayList(u8) = .{};
    try output.append(allocator, '"');
    for (value) |c| {
        if (c == '"' or c == '\\') {
            try output.append(allocator, '\\');
        }
        try output.append(allocator, c);
    }
    try output.append(allocator, '"');
    return output.toOwnedSlice(allocator);
}

/// Unquote a cookie value
pub fn unquote(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    return value;
}

// ============================================================================
// Tests
// ============================================================================

test "SimpleCookie basic" {
    const allocator = std.testing.allocator;
    var cookie = SimpleCookie.init(allocator);
    defer cookie.deinit();

    try cookie.set("session_id", "abc123");
    try std.testing.expect(cookie.contains("session_id"));

    if (cookie.get("session_id")) |morsel| {
        try std.testing.expectEqualStrings("abc123", morsel.value);
    } else {
        return error.TestUnexpectedResult;
    }
}

test "SimpleCookie load" {
    const allocator = std.testing.allocator;
    var cookie = SimpleCookie.init(allocator);
    defer cookie.deinit();

    try cookie.load("session_id=abc123; user=test");
    try std.testing.expect(cookie.contains("session_id"));
    try std.testing.expect(cookie.contains("user"));
}

test "Morsel outputString" {
    const allocator = std.testing.allocator;
    var morsel = Morsel.init(allocator, "session", "value123");
    morsel.secure = true;
    morsel.httponly = true;
    morsel.path = "/";

    const output = try morsel.outputString(allocator, null);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "session=value123") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Secure") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "HttpOnly") != null);
}

test "quote" {
    const allocator = std.testing.allocator;

    // No quoting needed
    const simple = try quote(allocator, "simple");
    defer allocator.free(simple);
    try std.testing.expectEqualStrings("simple", simple);

    // Needs quoting
    const quoted = try quote(allocator, "has;semicolon");
    defer allocator.free(quoted);
    try std.testing.expectEqualStrings("\"has;semicolon\"", quoted);
}

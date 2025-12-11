//! Python 'urllib.parse' module - URL parsing utilities
//!
//! Provides URL parsing, encoding/decoding, and query string handling.
//!
//! Mirrors: CPython Lib/urllib/parse.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Parsed URL components
pub const ParseResult = struct {
    scheme: []const u8,
    netloc: []const u8,
    path: []const u8,
    params: []const u8,
    query: []const u8,
    fragment: []const u8,

    /// Get the full URL
    pub fn geturl(self: ParseResult, allocator: std.mem.Allocator) ![]u8 {
        return urlunparse(allocator, self);
    }

    /// Get username from netloc
    pub fn username(self: ParseResult) ?[]const u8 {
        if (std.mem.indexOf(u8, self.netloc, "@")) |at_pos| {
            const userinfo = self.netloc[0..at_pos];
            if (std.mem.indexOf(u8, userinfo, ":")) |colon_pos| {
                return userinfo[0..colon_pos];
            }
            return userinfo;
        }
        return null;
    }

    /// Get password from netloc
    pub fn password(self: ParseResult) ?[]const u8 {
        if (std.mem.indexOf(u8, self.netloc, "@")) |at_pos| {
            const userinfo = self.netloc[0..at_pos];
            if (std.mem.indexOf(u8, userinfo, ":")) |colon_pos| {
                return userinfo[colon_pos + 1 ..];
            }
        }
        return null;
    }

    /// Get hostname from netloc
    pub fn hostname(self: ParseResult) ?[]const u8 {
        var host = self.netloc;

        // Remove userinfo
        if (std.mem.indexOf(u8, host, "@")) |at_pos| {
            host = host[at_pos + 1 ..];
        }

        // Remove port
        if (std.mem.lastIndexOf(u8, host, ":")) |colon_pos| {
            // Check if it's not IPv6
            if (host[0] != '[') {
                host = host[0..colon_pos];
            }
        }

        // Remove brackets for IPv6
        if (host.len > 2 and host[0] == '[' and host[host.len - 1] == ']') {
            host = host[1 .. host.len - 1];
        }

        if (host.len == 0) return null;
        return host;
    }

    /// Get port from netloc
    pub fn port(self: ParseResult) ?u16 {
        var host = self.netloc;

        // Remove userinfo
        if (std.mem.indexOf(u8, host, "@")) |at_pos| {
            host = host[at_pos + 1 ..];
        }

        // Handle IPv6 addresses
        if (host.len > 0 and host[0] == '[') {
            if (std.mem.indexOf(u8, host, "]:")) |bracket_pos| {
                const port_str = host[bracket_pos + 2 ..];
                return std.fmt.parseInt(u16, port_str, 10) catch null;
            }
            return null;
        }

        // Regular host:port
        if (std.mem.lastIndexOf(u8, host, ":")) |colon_pos| {
            const port_str = host[colon_pos + 1 ..];
            return std.fmt.parseInt(u16, port_str, 10) catch null;
        }

        return null;
    }
};

/// Split URL result (without params)
pub const SplitResult = struct {
    scheme: []const u8,
    netloc: []const u8,
    path: []const u8,
    query: []const u8,
    fragment: []const u8,

    pub fn geturl(self: SplitResult, allocator: std.mem.Allocator) ![]u8 {
        return urlunsplit(allocator, self);
    }

    pub fn hostname(self: SplitResult) ?[]const u8 {
        const pr = ParseResult{
            .scheme = self.scheme,
            .netloc = self.netloc,
            .path = self.path,
            .params = "",
            .query = self.query,
            .fragment = self.fragment,
        };
        return pr.hostname();
    }

    pub fn port(self: SplitResult) ?u16 {
        const pr = ParseResult{
            .scheme = self.scheme,
            .netloc = self.netloc,
            .path = self.path,
            .params = "",
            .query = self.query,
            .fragment = self.fragment,
        };
        return pr.port();
    }
};

/// Parse a URL into components
pub fn urlparse(url: []const u8) ParseResult {
    var scheme: []const u8 = "";
    var netloc: []const u8 = "";
    var path: []const u8 = "";
    var params: []const u8 = "";
    var query: []const u8 = "";
    var fragment: []const u8 = "";

    var remaining = url;

    // Extract fragment
    if (std.mem.indexOf(u8, remaining, "#")) |frag_pos| {
        fragment = remaining[frag_pos + 1 ..];
        remaining = remaining[0..frag_pos];
    }

    // Extract query
    if (std.mem.indexOf(u8, remaining, "?")) |query_pos| {
        query = remaining[query_pos + 1 ..];
        remaining = remaining[0..query_pos];
    }

    // Extract scheme
    if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
        scheme = remaining[0..scheme_end];
        remaining = remaining[scheme_end + 3 ..];

        // Extract netloc (until first /)
        if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
            netloc = remaining[0..path_start];
            remaining = remaining[path_start..];
        } else {
            netloc = remaining;
            remaining = "";
        }
    } else if (std.mem.indexOf(u8, remaining, ":")) |colon_pos| {
        // Could be scheme without //
        const possible_scheme = remaining[0..colon_pos];
        var is_scheme = true;
        for (possible_scheme) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') {
                is_scheme = false;
                break;
            }
        }
        if (is_scheme and possible_scheme.len > 0 and std.ascii.isAlphabetic(possible_scheme[0])) {
            scheme = possible_scheme;
            remaining = remaining[colon_pos + 1 ..];
        }
    }

    // Extract params (;params in path)
    if (std.mem.lastIndexOf(u8, remaining, ";")) |params_pos| {
        params = remaining[params_pos + 1 ..];
        remaining = remaining[0..params_pos];
    }

    path = remaining;

    return .{
        .scheme = scheme,
        .netloc = netloc,
        .path = path,
        .params = params,
        .query = query,
        .fragment = fragment,
    };
}

/// Split a URL into components (without params - params merged into path)
pub fn urlsplit(url: []const u8) SplitResult {
    const parsed = urlparse(url);
    // In urlsplit, params are merged with path using semicolon separator
    // For simplicity, we just return the path (params handling is rare)
    return .{
        .scheme = parsed.scheme,
        .netloc = parsed.netloc,
        .path = parsed.path, // Note: params are separate in parseResult but ignored in split
        .query = parsed.query,
        .fragment = parsed.fragment,
    };
}

/// Split URL with params merged into path (allocating version)
pub fn urlsplitWithParams(allocator: std.mem.Allocator, url: []const u8) !struct {
    result: SplitResult,
    path_with_params: []u8,
} {
    const parsed = urlparse(url);
    if (parsed.params.len > 0) {
        // Concatenate path;params
        const path_with_params = try std.fmt.allocPrint(allocator, "{s};{s}", .{ parsed.path, parsed.params });
        return .{
            .result = .{
                .scheme = parsed.scheme,
                .netloc = parsed.netloc,
                .path = path_with_params,
                .query = parsed.query,
                .fragment = parsed.fragment,
            },
            .path_with_params = path_with_params,
        };
    }
    return .{
        .result = .{
            .scheme = parsed.scheme,
            .netloc = parsed.netloc,
            .path = parsed.path,
            .query = parsed.query,
            .fragment = parsed.fragment,
        },
        .path_with_params = &[_]u8{},
    };
}

/// Reconstruct URL from components
pub fn urlunparse(allocator: std.mem.Allocator, components: ParseResult) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    if (components.scheme.len > 0) {
        try result.appendSlice(components.scheme);
        try result.appendSlice("://");
    }

    try result.appendSlice(components.netloc);
    try result.appendSlice(components.path);

    if (components.params.len > 0) {
        try result.append(';');
        try result.appendSlice(components.params);
    }

    if (components.query.len > 0) {
        try result.append('?');
        try result.appendSlice(components.query);
    }

    if (components.fragment.len > 0) {
        try result.append('#');
        try result.appendSlice(components.fragment);
    }

    return result.toOwnedSlice();
}

/// Reconstruct URL from split components
pub fn urlunsplit(allocator: std.mem.Allocator, components: SplitResult) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    if (components.scheme.len > 0) {
        try result.appendSlice(components.scheme);
        try result.appendSlice("://");
    }

    try result.appendSlice(components.netloc);
    try result.appendSlice(components.path);

    if (components.query.len > 0) {
        try result.append('?');
        try result.appendSlice(components.query);
    }

    if (components.fragment.len > 0) {
        try result.append('#');
        try result.appendSlice(components.fragment);
    }

    return result.toOwnedSlice();
}

/// Join a base URL with a relative URL
pub fn urljoin(allocator: std.mem.Allocator, base: []const u8, url: []const u8) ![]u8 {
    if (url.len == 0) {
        return allocator.dupe(u8, base);
    }

    const url_parsed = urlparse(url);

    // If url has scheme, it's absolute
    if (url_parsed.scheme.len > 0) {
        return allocator.dupe(u8, url);
    }

    const base_parsed = urlparse(base);

    var result = ParseResult{
        .scheme = base_parsed.scheme,
        .netloc = if (url_parsed.netloc.len > 0) url_parsed.netloc else base_parsed.netloc,
        .path = "",
        .params = url_parsed.params,
        .query = url_parsed.query,
        .fragment = url_parsed.fragment,
    };

    if (url_parsed.netloc.len > 0) {
        result.path = url_parsed.path;
    } else if (url_parsed.path.len == 0) {
        result.path = base_parsed.path;
        if (url_parsed.query.len == 0) {
            result.query = base_parsed.query;
        }
    } else if (url_parsed.path.len > 0 and url_parsed.path[0] == '/') {
        result.path = url_parsed.path;
    } else {
        // Relative path - merge with base
        if (std.mem.lastIndexOf(u8, base_parsed.path, "/")) |last_slash| {
            var merged = std.ArrayList(u8).init(allocator);
            defer merged.deinit();
            try merged.appendSlice(base_parsed.path[0 .. last_slash + 1]);
            try merged.appendSlice(url_parsed.path);
            result.path = try merged.toOwnedSlice();
        } else {
            result.path = url_parsed.path;
        }
    }

    return urlunparse(allocator, result);
}

/// Percent-encode a string
pub fn quote(allocator: std.mem.Allocator, s: []const u8, safe: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(c);
        } else if (std.mem.indexOfScalar(u8, safe, c) != null) {
            try result.append(c);
        } else {
            try result.append('%');
            const hex = "0123456789ABCDEF";
            try result.append(hex[c >> 4]);
            try result.append(hex[c & 0x0F]);
        }
    }

    return result.toOwnedSlice();
}

/// Percent-encode with space as +
pub fn quote_plus(allocator: std.mem.Allocator, s: []const u8, safe: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (s) |c| {
        if (c == ' ') {
            try result.append('+');
        } else if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(c);
        } else if (std.mem.indexOfScalar(u8, safe, c) != null) {
            try result.append(c);
        } else {
            try result.append('%');
            const hex = "0123456789ABCDEF";
            try result.append(hex[c >> 4]);
            try result.append(hex[c & 0x0F]);
        }
    }

    return result.toOwnedSlice();
}

/// Decode percent-encoded string
pub fn unquote(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hex = s[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex, 16)) |byte| {
                try result.append(byte);
                i += 3;
                continue;
            } else |_| {}
        }
        try result.append(s[i]);
        i += 1;
    }

    return result.toOwnedSlice();
}

/// Decode percent-encoded string, with + as space
pub fn unquote_plus(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '+') {
            try result.append(' ');
            i += 1;
        } else if (s[i] == '%' and i + 2 < s.len) {
            const hex = s[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex, 16)) |byte| {
                try result.append(byte);
                i += 3;
                continue;
            } else |_| {}
            try result.append(s[i]);
            i += 1;
        } else {
            try result.append(s[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

/// Encode query parameters
pub fn urlencode(allocator: std.mem.Allocator, params: []const struct { key: []const u8, value: []const u8 }) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (params, 0..) |param, i| {
        if (i > 0) try result.append('&');

        const key = try quote_plus(allocator, param.key, "");
        defer allocator.free(key);
        try result.appendSlice(key);

        try result.append('=');

        const value = try quote_plus(allocator, param.value, "");
        defer allocator.free(value);
        try result.appendSlice(value);
    }

    return result.toOwnedSlice();
}

/// Parse query string into key-value pairs
pub fn parse_qs(allocator: std.mem.Allocator, qs: []const u8) !hashmap_helper.StringHashMap(std.ArrayList([]const u8)) {
    var result = hashmap_helper.StringHashMap(std.ArrayList([]const u8)).init(allocator);

    var pairs = std.mem.splitScalar(u8, qs, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;

        var key: []const u8 = undefined;
        var value: []const u8 = "";

        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            key = try unquote_plus(allocator, pair[0..eq_pos]);
            value = try unquote_plus(allocator, pair[eq_pos + 1 ..]);
        } else {
            key = try unquote_plus(allocator, pair);
        }

        if (result.getPtr(key)) |list| {
            try list.append(value);
        } else {
            var list = std.ArrayList([]const u8).init(allocator);
            try list.append(value);
            try result.put(key, list);
        }
    }

    return result;
}

/// Parse query string into single key-value pairs (last value wins)
pub fn parse_qsl(allocator: std.mem.Allocator, qs: []const u8) ![]struct { key: []const u8, value: []const u8 } {
    var result = std.ArrayList(struct { key: []const u8, value: []const u8 }).init(allocator);

    var pairs = std.mem.splitScalar(u8, qs, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;

        var key: []const u8 = undefined;
        var value: []const u8 = "";

        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            key = try unquote_plus(allocator, pair[0..eq_pos]);
            value = try unquote_plus(allocator, pair[eq_pos + 1 ..]);
        } else {
            key = try unquote_plus(allocator, pair);
        }

        try result.append(.{ .key = key, .value = value });
    }

    return result.toOwnedSlice();
}

/// Default safe characters for quote
pub const SAFE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~";

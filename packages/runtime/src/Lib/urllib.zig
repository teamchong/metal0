//! Python 'urllib' module - URL handling utilities
//!
//! Provides URL parsing, encoding, and request handling.
//!
//! Mirrors: CPython Lib/urllib/

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// urllib.parse - URL parsing
// ============================================================================

pub const parse = struct {
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

    /// Split a URL into components (without params)
    pub fn urlsplit(url: []const u8) SplitResult {
        const parsed = urlparse(url);
        return .{
            .scheme = parsed.scheme,
            .netloc = parsed.netloc,
            .path = if (parsed.params.len > 0)
                // Would need to concat path;params
                parsed.path
            else
                parsed.path,
            .query = parsed.query,
            .fragment = parsed.fragment,
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
};

// ============================================================================
// urllib.request - URL request handling (stub)
// ============================================================================

pub const request = struct {
    /// URL opener
    pub const OpenerDirector = struct {
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) OpenerDirector {
            return .{ .allocator = allocator };
        }

        pub fn open(self: *OpenerDirector, url: []const u8) !Response {
            return urlopen(self.allocator, url);
        }
    };

    /// HTTP request
    pub const Request = struct {
        url: []const u8,
        method: []const u8,
        headers: hashmap_helper.StringHashMap([]const u8),
        data: ?[]const u8,

        pub fn init(allocator: std.mem.Allocator, url: []const u8) Request {
            return .{
                .url = url,
                .method = "GET",
                .headers = hashmap_helper.StringHashMap([]const u8).init(allocator),
                .data = null,
            };
        }

        pub fn addHeader(self: *Request, key: []const u8, value: []const u8) !void {
            try self.headers.put(key, value);
        }

        pub fn getMethod(self: *Request) []const u8 {
            return self.method;
        }

        pub fn getFullUrl(self: *Request) []const u8 {
            return self.url;
        }
    };

    /// HTTP response
    pub const Response = struct {
        url: []const u8,
        status: u16,
        reason: []const u8,
        headers: hashmap_helper.StringHashMap([]const u8),
        body: []const u8,
        allocator: std.mem.Allocator,

        pub fn read(self: *Response) []const u8 {
            return self.body;
        }

        pub fn getcode(self: *Response) u16 {
            return self.status;
        }

        pub fn getheader(self: *Response, name: []const u8) ?[]const u8 {
            return self.headers.get(name);
        }

        pub fn geturl(self: *Response) []const u8 {
            return self.url;
        }

        pub fn close(self: *Response) void {
            self.allocator.free(self.body);
            self.allocator.free(self.url);
            self.headers.deinit();
        }
    };

    /// Simple URL fetch using std.http.Client
    pub fn urlopen(allocator: std.mem.Allocator, url: []const u8) !Response {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const uri = std.Uri.parse(url) catch return error.URLError;

        var header_buf: [4096]u8 = undefined;
        var req = client.open(.GET, uri, .{
            .server_header_buffer = &header_buf,
        }) catch return error.URLError;
        defer req.deinit();

        req.send() catch return error.URLError;
        req.wait() catch return error.URLError;

        const body = req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch return error.URLError;

        var headers = hashmap_helper.StringHashMap([]const u8).init(allocator);

        return Response{
            .url = try allocator.dupe(u8, url),
            .status = @intFromEnum(req.status),
            .reason = "OK",
            .headers = headers,
            .body = body,
            .allocator = allocator,
        };
    }

    /// URL retrieve to file
    pub fn urlretrieve(allocator: std.mem.Allocator, url: []const u8, filename: ?[]const u8) !struct { filename: []const u8, headers: hashmap_helper.StringHashMap([]const u8) } {
        // Fetch the URL
        var response = try urlopen(allocator, url);
        defer response.close();

        // Determine output filename
        const out_filename = filename orelse blk: {
            // Extract filename from URL path
            const uri = std.Uri.parse(url) catch return error.URLError;
            const path = uri.path.percent_encoded;
            if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
                break :blk try allocator.dupe(u8, path[idx + 1 ..]);
            }
            break :blk try allocator.dupe(u8, "downloaded_file");
        };

        // Write to file
        const file = try std.fs.cwd().createFile(out_filename, .{});
        defer file.close();
        try file.writeAll(response.body);

        return .{
            .filename = out_filename,
            .headers = response.headers,
        };
    }

    /// Install opener
    pub fn install_opener(opener: *OpenerDirector) void {
        _ = opener;
        // Would install as default opener
    }

    /// Build opener with handlers
    pub fn build_opener(allocator: std.mem.Allocator) OpenerDirector {
        return OpenerDirector.init(allocator);
    }
};

// ============================================================================
// urllib.error - Exception classes
// ============================================================================

pub const Error = error{
    URLError,
    HTTPError,
    ContentTooShort,
    NotImplemented,
};

// ============================================================================
// urllib.robotparser - robots.txt parser
// ============================================================================

pub const robotparser = struct {
    pub const RobotFileParser = struct {
        allocator: std.mem.Allocator,
        url: ?[]const u8,
        disallow_all: bool,
        allow_all: bool,
        rules: std.ArrayList(Rule),

        const Rule = struct {
            useragent: []const u8,
            disallow: std.ArrayList([]const u8),
            allow: std.ArrayList([]const u8),
        };

        pub fn init(allocator: std.mem.Allocator, url: ?[]const u8) RobotFileParser {
            return .{
                .allocator = allocator,
                .url = url,
                .disallow_all = false,
                .allow_all = false,
                .rules = std.ArrayList(Rule).init(allocator),
            };
        }

        pub fn deinit(self: *RobotFileParser) void {
            for (self.rules.items) |*rule| {
                rule.disallow.deinit();
                rule.allow.deinit();
            }
            self.rules.deinit();
        }

        pub fn setUrl(self: *RobotFileParser, url: []const u8) void {
            self.url = url;
        }

        pub fn read(self: *RobotFileParser) !void {
            if (self.url) |url| {
                // Fetch robots.txt using HTTP
                var client = std.http.Client{ .allocator = self.allocator };
                defer client.deinit();

                const uri = std.Uri.parse(url) catch return;
                var req = client.open(.GET, uri, .{}) catch return;
                defer req.deinit();

                req.send() catch return;
                req.wait() catch return;

                // Read response body
                var body_buf: [64 * 1024]u8 = undefined;
                const body_len = req.reader().readAll(&body_buf) catch return;
                const body = body_buf[0..body_len];

                // Split into lines and parse
                var lines = std.ArrayList([]const u8).init(self.allocator);
                defer lines.deinit();

                var iter = std.mem.splitScalar(u8, body, '\n');
                while (iter.next()) |line| {
                    lines.append(line) catch continue;
                }

                try self.parse(lines.items);
            }
        }

        pub fn parse(self: *RobotFileParser, lines: []const []const u8) !void {
            var current_useragent: ?[]const u8 = null;
            var current_rule: ?*Rule = null;

            for (lines) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r\n");
                if (trimmed.len == 0 or trimmed[0] == '#') continue;

                if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                    const key = std.mem.trim(u8, trimmed[0..colon_pos], " \t");
                    const value = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " \t");

                    if (std.ascii.eqlIgnoreCase(key, "user-agent")) {
                        current_useragent = value;
                        try self.rules.append(.{
                            .useragent = value,
                            .disallow = std.ArrayList([]const u8).init(self.allocator),
                            .allow = std.ArrayList([]const u8).init(self.allocator),
                        });
                        current_rule = &self.rules.items[self.rules.items.len - 1];
                    } else if (current_rule) |rule| {
                        if (std.ascii.eqlIgnoreCase(key, "disallow")) {
                            try rule.disallow.append(value);
                        } else if (std.ascii.eqlIgnoreCase(key, "allow")) {
                            try rule.allow.append(value);
                        }
                    }
                }
            }
            _ = current_useragent;
        }

        pub fn canFetch(self: *RobotFileParser, useragent: []const u8, url: []const u8) bool {
            if (self.disallow_all) return false;
            if (self.allow_all) return true;

            const parsed = parse.urlparse(url);

            for (self.rules.items) |rule| {
                if (std.mem.eql(u8, rule.useragent, "*") or
                    std.mem.indexOf(u8, useragent, rule.useragent) != null)
                {
                    // Check allow first
                    for (rule.allow.items) |pattern| {
                        if (std.mem.startsWith(u8, parsed.path, pattern)) {
                            return true;
                        }
                    }
                    // Then disallow
                    for (rule.disallow.items) |pattern| {
                        if (pattern.len == 0) continue;
                        if (std.mem.startsWith(u8, parsed.path, pattern)) {
                            return false;
                        }
                    }
                }
            }

            return true;
        }

        pub fn mtime(self: *RobotFileParser) ?i64 {
            _ = self;
            return null;
        }

        pub fn modified(self: *RobotFileParser) void {
            _ = self;
            // Update mtime
        }
    };
};

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

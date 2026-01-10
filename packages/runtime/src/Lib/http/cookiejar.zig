//! http.cookiejar - HTTP cookie management
//! Reference: cpython/Lib/http/cookiejar.py
//!
//! CPython __all__: CookieJar, FileCookieJar, LWPCookieJar, MozillaCookieJar,
//!                  Cookie, DefaultCookiePolicy
//!
//! HTTP cookie management with persistent storage support.

const std = @import("std");
const cookies = @import("cookies.zig");

/// Cookie object representing a single HTTP cookie
pub const Cookie = struct {
    const Self = @This();

    version: u8,
    name: []const u8,
    value: []const u8,
    port: ?[]const u8,
    port_specified: bool,
    domain: []const u8,
    domain_specified: bool,
    domain_initial_dot: bool,
    path: []const u8,
    path_specified: bool,
    secure: bool,
    expires: ?i64,
    discard: bool,
    comment: ?[]const u8,
    comment_url: ?[]const u8,
    rfc2109: bool,

    pub fn init(name: []const u8, value: []const u8) Self {
        return .{
            .version = 0,
            .name = name,
            .value = value,
            .port = null,
            .port_specified = false,
            .domain = "",
            .domain_specified = false,
            .domain_initial_dot = false,
            .path = "/",
            .path_specified = false,
            .secure = false,
            .expires = null,
            .discard = true,
            .comment = null,
            .comment_url = null,
            .rfc2109 = false,
        };
    }

    /// Check if cookie has expired
    pub fn isExpired(self: *const Self, now: ?i64) bool {
        if (self.expires) |exp| {
            const current = now orelse std.time.timestamp();
            return exp <= current;
        }
        return false;
    }

    /// Check if cookie matches a domain
    pub fn domainMatches(self: *const Self, domain: []const u8) bool {
        if (std.mem.eql(u8, self.domain, domain)) return true;
        if (self.domain_initial_dot) {
            // .example.com matches foo.example.com
            if (std.mem.endsWith(u8, domain, self.domain)) return true;
        }
        return false;
    }

    /// Check if cookie matches a path
    pub fn pathMatches(self: *const Self, path: []const u8) bool {
        if (std.mem.eql(u8, self.path, path)) return true;
        if (std.mem.startsWith(u8, path, self.path)) {
            if (self.path[self.path.len - 1] == '/') return true;
            if (path.len > self.path.len and path[self.path.len] == '/') return true;
        }
        return false;
    }
};

/// Cookie policy for accept/reject decisions
pub const DefaultCookiePolicy = struct {
    const Self = @This();

    netscape: bool = true,
    rfc2965: bool = false,
    rfc2109_as_netscape: bool = true,
    hide_cookie2: bool = false,
    strict_domain: bool = false,
    strict_rfc2965_unverifiable: bool = true,
    strict_ns_unverifiable: bool = false,
    strict_ns_domain: u8 = 0,
    strict_ns_set_initial_dollar: bool = false,
    strict_ns_set_path: bool = false,

    allowed_domains: ?std.StringHashMap(void) = null,
    blocked_domains: ?std.StringHashMap(void) = null,

    /// Check if a domain is allowed
    pub fn domainAllowed(self: *const Self, domain: []const u8) bool {
        if (self.blocked_domains) |blocked| {
            if (blocked.contains(domain)) return false;
        }
        if (self.allowed_domains) |allowed| {
            return allowed.contains(domain);
        }
        return true;
    }

    /// Set allowed domains
    pub fn setAllowedDomains(self: *Self, allocator: std.mem.Allocator, domains: []const []const u8) !void {
        self.allowed_domains = std.StringHashMap(void).init(allocator);
        for (domains) |domain| {
            try self.allowed_domains.?.put(domain, {});
        }
    }

    /// Set blocked domains
    pub fn setBlockedDomains(self: *Self, allocator: std.mem.Allocator, domains: []const []const u8) !void {
        self.blocked_domains = std.StringHashMap(void).init(allocator);
        for (domains) |domain| {
            try self.blocked_domains.?.put(domain, {});
        }
    }
};

/// Cookie jar - stores and manages cookies
pub const CookieJar = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    cookies: std.ArrayList(Cookie),
    policy: DefaultCookiePolicy,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cookies = std.ArrayList(Cookie).init(allocator),
            .policy = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.cookies.deinit(self.allocator);
    }

    /// Add a cookie
    pub fn setCookie(self: *Self, cookie: Cookie) !void {
        // Check policy
        if (!self.policy.domainAllowed(cookie.domain)) return;

        // Remove existing cookie with same name/domain/path
        self.removeCookie(cookie.name, cookie.domain, cookie.path);

        try self.cookies.append(self.allocator, cookie);
    }

    /// Remove a specific cookie
    pub fn removeCookie(self: *Self, name: []const u8, domain: []const u8, path: []const u8) void {
        var i: usize = 0;
        while (i < self.cookies.items.len) {
            const c = &self.cookies.items[i];
            if (std.mem.eql(u8, c.name, name) and
                std.mem.eql(u8, c.domain, domain) and
                std.mem.eql(u8, c.path, path))
            {
                _ = self.cookies.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Clear all cookies
    pub fn clear(self: *Self) void {
        self.cookies.clearRetainingCapacity();
    }

    /// Clear expired cookies
    pub fn clearExpired(self: *Self) void {
        const now = std.time.timestamp();
        var i: usize = 0;
        while (i < self.cookies.items.len) {
            if (self.cookies.items[i].isExpired(now)) {
                _ = self.cookies.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get cookies for a URL
    pub fn cookiesForRequest(self: *Self, allocator: std.mem.Allocator, domain: []const u8, path: []const u8, secure: bool) !std.ArrayList(*Cookie) {
        var result: std.ArrayList(*Cookie) = .{};

        for (self.cookies.items) |*cookie| {
            if (cookie.isExpired(null)) continue;
            if (!cookie.domainMatches(domain)) continue;
            if (!cookie.pathMatches(path)) continue;
            if (cookie.secure and !secure) continue;

            try result.append(allocator, cookie);
        }

        return result;
    }

    /// Get cookie header value for request
    pub fn getCookieHeader(self: *Self, allocator: std.mem.Allocator, domain: []const u8, path: []const u8, secure: bool) !?[]const u8 {
        var matching = try self.cookiesForRequest(allocator, domain, path, secure);
        defer matching.deinit(allocator);

        if (matching.items.len == 0) return null;

        var output: std.ArrayList(u8) = .{};
        for (matching.items, 0..) |cookie, i| {
            if (i > 0) try output.appendSlice(allocator, "; ");
            try output.appendSlice(allocator, cookie.name);
            try output.append(allocator, '=');
            try output.appendSlice(allocator, cookie.value);
        }

        return output.toOwnedSlice(allocator);
    }

    /// Number of cookies
    pub fn count(self: *const Self) usize {
        return self.cookies.items.len;
    }
};

/// File-based cookie jar
pub const FileCookieJar = struct {
    const Self = @This();

    jar: CookieJar,
    filename: []const u8,
    delayload: bool,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) Self {
        return .{
            .jar = CookieJar.init(allocator),
            .filename = filename,
            .delayload = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.jar.deinit();
    }

    /// Save cookies to file
    pub fn save(self: *Self) !void {
        _ = self;
        // Would write cookies to file
    }

    /// Load cookies from file
    pub fn load(self: *Self) !void {
        _ = self;
        // Would read cookies from file
    }
};

/// Mozilla-format cookie jar (cookies.txt)
pub const MozillaCookieJar = FileCookieJar;

/// LWP-format cookie jar
pub const LWPCookieJar = FileCookieJar;

// ============================================================================
// Tests
// ============================================================================

test "Cookie basic" {
    var cookie = Cookie.init("session", "abc123");
    cookie.domain = "example.com";
    cookie.secure = true;

    try std.testing.expectEqualStrings("session", cookie.name);
    try std.testing.expectEqualStrings("abc123", cookie.value);
    try std.testing.expect(cookie.secure);
}

test "Cookie isExpired" {
    var cookie = Cookie.init("test", "value");
    cookie.expires = 1; // Very old timestamp
    try std.testing.expect(cookie.isExpired(null));

    cookie.expires = std.time.timestamp() + 3600;
    try std.testing.expect(!cookie.isExpired(null));
}

test "CookieJar basic" {
    const allocator = std.testing.allocator;
    var jar = CookieJar.init(allocator);
    defer jar.deinit();

    var cookie = Cookie.init("session", "value");
    cookie.domain = "example.com";
    try jar.setCookie(cookie);

    try std.testing.expectEqual(@as(usize, 1), jar.count());
}

test "DefaultCookiePolicy" {
    var policy = DefaultCookiePolicy{};
    try std.testing.expect(policy.domainAllowed("example.com"));
}

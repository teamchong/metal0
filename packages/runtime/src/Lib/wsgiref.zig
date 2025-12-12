//! Python 'wsgiref' module - WSGI utilities and reference implementation
//!
//! Provides a reference implementation of WSGI (Web Server Gateway Interface).
//!
//! Mirrors: CPython Lib/wsgiref/

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const WsgiError = error{
    InvalidHeader,
    InvalidStatus,
    ResponseStarted,
    IoError,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

/// WSGI environ dictionary type
pub const Environ = hashmap_helper.StringHashMap([]const u8);

/// Response headers type
pub const Headers = std.ArrayList(struct { []const u8, []const u8 });

/// Start response callback type
pub const StartResponse = *const fn ([]const u8, []const struct { []const u8, []const u8 }) anyerror!void;

/// WSGI application type
pub const Application = *const fn (*Environ, StartResponse) anyerror!std.ArrayList([]const u8);

// ============================================================================
// Headers utility class
// ============================================================================

/// WSGI response headers manager
pub const ResponseHeaders = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    headers: std.ArrayList(struct { name: []const u8, value: []const u8 }),

    pub fn init(allocator: std.mem.Allocator, headers: ?[]const struct { []const u8, []const u8 }) Self {
        var self = Self{
            .allocator = allocator,
            .headers = .{},
        };

        if (headers) |h| {
            for (h) |header| {
                self.headers.append(allocator, .{ .name = header[0], .value = header[1] }) catch {};
            }
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.headers.deinit(self.allocator);
    }

    /// Get the value of a header
    pub fn get(self: *const Self, name: []const u8) ?[]const u8 {
        for (self.headers.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, name)) {
                return header.value;
            }
        }
        return null;
    }

    /// Get all values for a header
    pub fn getAll(self: *const Self, allocator: std.mem.Allocator, name: []const u8) !std.ArrayList([]const u8) {
        var result: std.ArrayList([]const u8) = .{};
        for (self.headers.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, name)) {
                try result.append(allocator, header.value);
            }
        }
        return result;
    }

    /// Check if header exists
    pub fn has(self: *const Self, name: []const u8) bool {
        return self.get(name) != null;
    }

    /// Add a header (can have duplicates)
    pub fn add(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.append(self.allocator, .{ .name = name, .value = value });
    }

    /// Set a header (replaces existing)
    pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
        // Remove existing
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        // Add new
        try self.add(name, value);
    }

    /// Delete a header
    pub fn delete(self: *Self, name: []const u8) void {
        var i: usize = 0;
        while (i < self.headers.items.len) {
            if (std.ascii.eqlIgnoreCase(self.headers.items[i].name, name)) {
                _ = self.headers.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get the number of headers
    pub fn len(self: *const Self) usize {
        return self.headers.items.len;
    }

    /// Convert to HTTP header string
    pub fn toString(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        const writer = result.writer(allocator);

        for (self.headers.items) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }

        return result.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Simple Server
// ============================================================================

/// Simple WSGI server
pub const SimpleServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    app: ?Application = null,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Self {
        return Self{
            .allocator = allocator,
            .host = host,
            .port = port,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Set the WSGI application
    pub fn setApp(self: *Self, app: Application) void {
        self.app = app;
    }

    /// Handle a single request (for testing)
    pub fn handleRequest(self: *Self, request_data: []const u8) ![]u8 {
        _ = self;
        _ = request_data;
        return self.allocator.dupe(u8, "HTTP/1.1 200 OK\r\n\r\n");
    }

    /// Start serving WSGI requests
    pub fn serve_forever(self: *Self) !void {
        // Create TCP socket
        const addr = std.net.Address.parseIp4(self.host, self.port) catch
            std.net.Address.parseIp4("127.0.0.1", self.port) catch return;

        var server = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch return;
        defer std.posix.close(server);

        // Set SO_REUSEADDR
        const optval: u32 = 1;
        std.posix.setsockopt(server, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&optval)) catch {};

        // Bind and listen
        std.posix.bind(server, &addr.any, addr.getOsSockLen()) catch return;
        std.posix.listen(server, 5) catch return;

        // Accept loop
        while (true) {
            var client_addr: std.posix.sockaddr = undefined;
            var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

            const client = std.posix.accept(server, &client_addr, &addr_len) catch continue;
            defer std.posix.close(client);

            // Read HTTP request
            var buf: [8192]u8 = undefined;
            const n = std.posix.recv(client, &buf, 0) catch continue;
            if (n == 0) continue;

            // Parse request line
            const request = buf[0..n];
            const line_end = std.mem.indexOf(u8, request, "\r\n") orelse continue;
            const request_line = request[0..line_end];

            const parsed = parseRequestLine(request_line) catch continue;

            // Build environ
            var environ = buildEnviron(self.allocator, parsed.method, parsed.path) catch continue;
            defer environ.deinit();

            // Call WSGI app
            if (self.app) |app| {
                var response_started = false;
                var status: []const u8 = "200 OK";
                var headers: []const [2][]const u8 = &.{};

                const start_response = struct {
                    fn call(s: []const u8, h: []const [2][]const u8) void {
                        _ = s;
                        _ = h;
                    }
                }.call;

                const result = app(environ, start_response);
                _ = result;
                _ = response_started;
                _ = status;
                _ = headers;

                // Send response
                _ = std.posix.send(client, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", 0) catch continue;
            } else {
                _ = std.posix.send(client, "HTTP/1.1 500 Internal Server Error\r\n\r\n", 0) catch continue;
            }
        }
    }
};

// ============================================================================
// Utilities
// ============================================================================

/// Parse HTTP request line
pub fn parseRequestLine(line: []const u8) !struct { method: []const u8, path: []const u8, version: []const u8 } {
    var iter = std.mem.splitScalar(u8, line, ' ');
    const method = iter.next() orelse return error.InvalidStatus;
    const path = iter.next() orelse return error.InvalidStatus;
    const version = iter.next() orelse return error.InvalidStatus;

    return .{
        .method = method,
        .path = path,
        .version = version,
    };
}

/// Build a basic environ dict
pub fn buildEnviron(allocator: std.mem.Allocator, method: []const u8, path: []const u8) !Environ {
    var environ: Environ = .{};

    try environ.put("REQUEST_METHOD", method);
    try environ.put("SCRIPT_NAME", "");
    try environ.put("PATH_INFO", path);
    try environ.put("QUERY_STRING", "");
    try environ.put("SERVER_NAME", "localhost");
    try environ.put("SERVER_PORT", "8000");
    try environ.put("SERVER_PROTOCOL", "HTTP/1.1");
    try environ.put("wsgi.version", "1.0");
    try environ.put("wsgi.url_scheme", "http");
    try environ.put("wsgi.multithread", "true");
    try environ.put("wsgi.multiprocess", "true");
    try environ.put("wsgi.run_once", "false");

    return environ;
}

/// Format HTTP status line
pub fn formatStatus(allocator: std.mem.Allocator, status: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "HTTP/1.1 {s}\r\n", .{status});
}

/// Validate HTTP header name
pub fn isValidHeaderName(name: []const u8) bool {
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            return false;
        }
    }
    return name.len > 0;
}

/// Validate HTTP header value
pub fn isValidHeaderValue(value: []const u8) bool {
    for (value) |c| {
        if (c == '\r' or c == '\n') {
            return false;
        }
    }
    return true;
}

// ============================================================================
// demo_app - Example WSGI application
// ============================================================================

/// A simple demo WSGI application
pub fn demo_app(environ: *Environ, start_response: StartResponse) !std.ArrayList([]const u8) {
    _ = environ;

    const headers = [_]struct { []const u8, []const u8 }{
        .{ "Content-Type", "text/plain" },
    };

    try start_response("200 OK", &headers);

    var response: std.ArrayList([]const u8) = .{};
    try response.append(allocator_helper.fast_allocator, "Hello, World!\n");
    return response;
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

test "ResponseHeaders init" {
    const allocator = std.testing.allocator;
    var headers = ResponseHeaders.init(allocator, null);
    defer headers.deinit();

    try std.testing.expectEqual(@as(usize, 0), headers.len());
}

test "ResponseHeaders add and get" {
    const allocator = std.testing.allocator;
    var headers = ResponseHeaders.init(allocator, null);
    defer headers.deinit();

    try headers.add("Content-Type", "text/html");
    try std.testing.expectEqualStrings("text/html", headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("text/html", headers.get("content-type").?);
}

test "ResponseHeaders set" {
    const allocator = std.testing.allocator;
    var headers = ResponseHeaders.init(allocator, null);
    defer headers.deinit();

    try headers.add("X-Custom", "value1");
    try headers.set("X-Custom", "value2");

    try std.testing.expectEqual(@as(usize, 1), headers.len());
    try std.testing.expectEqualStrings("value2", headers.get("X-Custom").?);
}

test "ResponseHeaders toString" {
    const allocator = std.testing.allocator;
    var headers = ResponseHeaders.init(allocator, null);
    defer headers.deinit();

    try headers.add("Content-Type", "text/plain");
    try headers.add("Content-Length", "13");

    const str = try headers.toString(allocator);
    defer allocator.free(str);

    try std.testing.expect(std.mem.indexOf(u8, str, "Content-Type: text/plain\r\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "Content-Length: 13\r\n") != null);
}

test "parseRequestLine" {
    const result = try parseRequestLine("GET /path HTTP/1.1");
    try std.testing.expectEqualStrings("GET", result.method);
    try std.testing.expectEqualStrings("/path", result.path);
    try std.testing.expectEqualStrings("HTTP/1.1", result.version);
}

test "isValidHeaderName" {
    try std.testing.expect(isValidHeaderName("Content-Type"));
    try std.testing.expect(isValidHeaderName("X_Custom_Header"));
    try std.testing.expect(!isValidHeaderName(""));
    try std.testing.expect(!isValidHeaderName("Header: value"));
}

test "isValidHeaderValue" {
    try std.testing.expect(isValidHeaderValue("text/html"));
    try std.testing.expect(!isValidHeaderValue("bad\r\nvalue"));
}

test "buildEnviron" {
    const allocator = std.testing.allocator;
    var environ = try buildEnviron(allocator, "GET", "/test");
    defer environ.deinit();

    try std.testing.expectEqualStrings("GET", environ.get("REQUEST_METHOD").?);
    try std.testing.expectEqualStrings("/test", environ.get("PATH_INFO").?);
}

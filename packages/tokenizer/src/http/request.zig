/// HTTP Request type with zero-copy parsing
const std = @import("std");
const runtime = @import("../runtime.zig");

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,

    pub fn fromString(s: []const u8) !Method {
        if (std.mem.eql(u8, s, "GET")) return .GET;
        if (std.mem.eql(u8, s, "POST")) return .POST;
        if (std.mem.eql(u8, s, "PUT")) return .PUT;
        if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
        return error.InvalidMethod;
    }

    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .PATCH => "PATCH",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
        };
    }
};

pub const Headers = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Headers {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Headers) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn set(self: *Headers, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        try self.map.put(key_copy, value_copy);
    }

    pub fn get(self: *const Headers, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn contains(self: *const Headers, key: []const u8) bool {
        return self.map.contains(key);
    }

    pub fn count(self: *const Headers) usize {
        return self.map.count();
    }
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    version: []const u8,
    headers: Headers,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, method: Method, path: []const u8) !Request {
        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);

        return .{
            .method = method,
            .path = path_copy,
            .version = "HTTP/1.1",
            .headers = Headers.init(allocator),
            .body = &[_]u8{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Request) void {
        self.allocator.free(self.path);
        self.headers.deinit();
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

    pub fn setHeader(self: *Request, key: []const u8, value: []const u8) !void {
        try self.headers.set(key, value);
    }

    pub fn setBody(self: *Request, body: []const u8) !void {
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
        self.body = try self.allocator.dupe(u8, body);
    }

    pub fn setJsonBody(self: *Request, json: []const u8) !void {
        try self.setBody(json);
        try self.setHeader("Content-Type", "application/json");
        var buf: [32]u8 = undefined;
        const len_str = try std.fmt.bufPrint(&buf, "{d}", .{json.len});
        try self.setHeader("Content-Length", len_str);
    }

    /// Serialize request to HTTP format
    pub fn serialize(self: *const Request, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8){};
        const writer = buf.writer(allocator);

        // Request line
        try writer.print("{s} {s} {s}\r\n", .{ self.method.toString(), self.path, self.version });

        // Headers
        var it = self.headers.map.iterator();
        while (it.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Empty line
        try writer.writeAll("\r\n");

        // Body
        if (self.body.len > 0) {
            try writer.writeAll(self.body);
        }

        return try buf.toOwnedSlice(allocator);
    }

    /// Parse HTTP request from raw bytes (zero-copy where possible)
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Request {
        var lines = std.mem.splitSequence(u8, data, "\r\n");

        // Parse request line
        const request_line = lines.next() orelse return error.InvalidRequest;
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method_str = parts.next() orelse return error.InvalidMethod;
        const path = parts.next() orelse return error.InvalidPath;
        const version = parts.next() orelse return error.InvalidVersion;

        const method = try Method.fromString(method_str);
        var request = try Request.init(allocator, method, path);
        errdefer request.deinit();

        request.version = version;

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break; // End of headers

            const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
            const key = std.mem.trim(u8, line[0..colon_pos], " \t");
            const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");

            try request.setHeader(key, value);
        }

        // Parse body (remaining data after headers)
        const header_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse data.len;
        if (header_end + 4 < data.len) {
            const body = data[header_end + 4 ..];
            try request.setBody(body);
        }

        return request;
    }
};

test "Request creation and serialization" {
    const allocator = std.testing.allocator;

    var request = try Request.init(allocator, .GET, "/api/users");
    defer request.deinit();

    try request.setHeader("Host", "example.com");
    try request.setHeader("User-Agent", "PyAOT/1.0");

    const serialized = try request.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expect(std.mem.indexOf(u8, serialized, "GET /api/users HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "Host: example.com") != null);
}

test "Request parsing" {
    const allocator = std.testing.allocator;

    const raw_request =
        \\GET /api/users HTTP/1.1
        \\Host: example.com
        \\User-Agent: PyAOT/1.0
        \\
        \\
    ;

    var request = try Request.parse(allocator, raw_request);
    defer request.deinit();

    try std.testing.expectEqual(Method.GET, request.method);
    try std.testing.expectEqualStrings("/api/users", request.path);
    try std.testing.expectEqualStrings("example.com", request.headers.get("Host").?);
}

test "Request with JSON body" {
    const allocator = std.testing.allocator;

    var request = try Request.init(allocator, .POST, "/api/data");
    defer request.deinit();

    const json = "{\"test\": \"value\"}";
    try request.setJsonBody(json);

    try std.testing.expectEqualStrings(json, request.body);
    try std.testing.expectEqualStrings("application/json", request.headers.get("Content-Type").?);
}

/// HTTP Response type with zero-copy parsing
const std = @import("std");
const runtime = @import("../runtime.zig");
const Headers = @import("request.zig").Headers;

pub const Status = enum(u16) {
    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,

    // 3xx Redirection
    moved_permanently = 301,
    found = 302,
    see_other = 303,
    not_modified = 304,
    temporary_redirect = 307,
    permanent_redirect = 308,

    // 4xx Client Error
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    conflict = 409,
    unprocessable_entity = 422,

    // 5xx Server Error
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,
    gateway_timeout = 504,

    pub fn fromCode(code: u16) Status {
        return @enumFromInt(code);
    }

    pub fn toCode(self: Status) u16 {
        return @intFromEnum(self);
    }

    pub fn reason(self: Status) []const u8 {
        return switch (self) {
            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .no_content => "No Content",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .see_other => "See Other",
            .not_modified => "Not Modified",
            .temporary_redirect => "Temporary Redirect",
            .permanent_redirect => "Permanent Redirect",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .conflict => "Conflict",
            .unprocessable_entity => "Unprocessable Entity",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
            .gateway_timeout => "Gateway Timeout",
        };
    }
};

pub const Response = struct {
    status: Status,
    version: []const u8,
    headers: Headers,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, status: Status) Response {
        return .{
            .status = status,
            .version = "HTTP/1.1",
            .headers = Headers.init(allocator),
            .body = &[_]u8{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

    pub fn setHeader(self: *Response, key: []const u8, value: []const u8) !void {
        try self.headers.set(key, value);
    }

    pub fn setBody(self: *Response, body: []const u8) !void {
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
        self.body = try self.allocator.dupe(u8, body);

        // Auto-set Content-Length
        var buf: [32]u8 = undefined;
        const len_str = try std.fmt.bufPrint(&buf, "{d}", .{body.len});
        try self.setHeader("Content-Length", len_str);
    }

    pub fn setJsonBody(self: *Response, json_data: []const u8) !void {
        try self.setBody(json_data);
        try self.setHeader("Content-Type", "application/json");
    }

    pub fn setTextBody(self: *Response, text_data: []const u8) !void {
        try self.setBody(text_data);
        try self.setHeader("Content-Type", "text/plain");
    }

    pub fn setHtmlBody(self: *Response, html: []const u8) !void {
        try self.setBody(html);
        try self.setHeader("Content-Type", "text/html");
    }

    /// Serialize response to HTTP format
    pub fn serialize(self: *const Response, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8){};
        const writer = buf.writer(allocator);

        // Status line
        try writer.print("{s} {d} {s}\r\n", .{ self.version, self.status.toCode(), self.status.reason() });

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

    /// Parse HTTP response from raw bytes (zero-copy where possible)
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Response {
        var lines = std.mem.splitSequence(u8, data, "\r\n");

        // Parse status line
        const status_line = lines.next() orelse return error.InvalidResponse;
        var parts = std.mem.splitScalar(u8, status_line, ' ');
        const version = parts.next() orelse return error.InvalidVersion;
        const status_code_str = parts.next() orelse return error.InvalidStatusCode;
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        var response = Response.init(allocator, Status.fromCode(status_code));
        errdefer response.deinit();

        response.version = version;

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break; // End of headers

            const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
            const key = std.mem.trim(u8, line[0..colon_pos], " \t");
            const value = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");

            try response.setHeader(key, value);
        }

        // Parse body (remaining data after headers)
        const header_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse data.len;
        if (header_end + 4 < data.len) {
            const body = data[header_end + 4 ..];

            // Check Content-Length to handle chunked encoding properly
            if (response.headers.get("Content-Length")) |len_str| {
                const content_length = try std.fmt.parseInt(usize, len_str, 10);
                const actual_body = body[0..@min(content_length, body.len)];
                response.body = try allocator.dupe(u8, actual_body);
            } else {
                response.body = try allocator.dupe(u8, body);
            }
        }

        return response;
    }

    /// Get status code as integer
    pub fn statusCode(self: *const Response) u16 {
        return self.status.toCode();
    }

    /// Check if response is successful (2xx)
    pub fn isSuccess(self: *const Response) bool {
        const code = self.statusCode();
        return code >= 200 and code < 300;
    }

    /// Check if response is redirect (3xx)
    pub fn isRedirect(self: *const Response) bool {
        const code = self.statusCode();
        return code >= 300 and code < 400;
    }

    /// Check if response is client error (4xx)
    pub fn isClientError(self: *const Response) bool {
        const code = self.statusCode();
        return code >= 400 and code < 500;
    }

    /// Check if response is server error (5xx)
    pub fn isServerError(self: *const Response) bool {
        const code = self.statusCode();
        return code >= 500 and code < 600;
    }

    /// Parse JSON body (requires json module)
    pub fn json(self: *const Response, allocator: std.mem.Allocator) !std.json.Value {
        if (self.body.len == 0) return error.EmptyBody;
        return try std.json.parseFromSlice(std.json.Value, allocator, self.body, .{});
    }

    /// Get body as string
    pub fn text(self: *const Response) []const u8 {
        return self.body;
    }
};

test "Response creation and serialization" {
    const allocator = std.testing.allocator;

    var response = Response.init(allocator, .ok);
    defer response.deinit();

    try response.setTextBody("Hello, World!");
    try response.setHeader("Server", "PyAOT/1.0");

    const serialized = try response.serialize(allocator);
    defer allocator.free(serialized);

    try std.testing.expect(std.mem.indexOf(u8, serialized, "HTTP/1.1 200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "Hello, World!") != null);
}

test "Response parsing" {
    const allocator = std.testing.allocator;

    const raw_response =
        \\HTTP/1.1 200 OK
        \\Content-Type: text/plain
        \\Content-Length: 13
        \\
        \\Hello, World!
    ;

    var response = try Response.parse(allocator, raw_response);
    defer response.deinit();

    try std.testing.expectEqual(Status.ok, response.status);
    try std.testing.expectEqualStrings("Hello, World!", response.body);
    try std.testing.expect(response.isSuccess());
}

test "Response status helpers" {
    const allocator = std.testing.allocator;

    var ok = Response.init(allocator, .ok);
    defer ok.deinit();
    try std.testing.expect(ok.isSuccess());
    try std.testing.expect(!ok.isClientError());

    var not_found = Response.init(allocator, .not_found);
    defer not_found.deinit();
    try std.testing.expect(not_found.isClientError());
    try std.testing.expect(!not_found.isSuccess());

    var server_error = Response.init(allocator, .internal_server_error);
    defer server_error.deinit();
    try std.testing.expect(server_error.isServerError());
}

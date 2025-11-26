/// HTTP Client with connection pooling and builder pattern
const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Method = @import("request.zig").Method;
const Status = @import("response.zig").Status;
const ConnectionPool = @import("pool.zig").ConnectionPool;
const hashmap_helper = @import("hashmap_helper");

pub const ClientError = error{
    InvalidUrl,
    ConnectionFailed,
    RequestFailed,
    ResponseParseFailed,
    Timeout,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    pool: ConnectionPool,
    timeout_ms: u64,
    default_headers: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Client {
        return .{
            .allocator = allocator,
            .pool = ConnectionPool.init(allocator, 100), // Max 100 connections
            .timeout_ms = 30000, // 30 second default timeout
            .default_headers = hashmap_helper.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Client) void {
        self.pool.deinit();
        var it = self.default_headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.default_headers.deinit();
    }

    /// Set default header for all requests
    pub fn setDefaultHeader(self: *Client, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        try self.default_headers.put(key_copy, value_copy);
    }

    /// Simple GET request
    pub fn get(self: *Client, url: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .GET, uri.path.raw);
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", uri.host orelse "");

        return try self.send(&request, &uri);
    }

    /// Simple POST request
    pub fn post(self: *Client, url: []const u8, body: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .POST, uri.path.raw);
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", uri.host orelse "");
        try request.setBody(body);

        return try self.send(&request, &uri);
    }

    /// POST with JSON body
    pub fn postJson(self: *Client, url: []const u8, json: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .POST, uri.path.raw);
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", uri.host orelse "");
        try request.setJsonBody(json);

        return try self.send(&request, &uri);
    }

    /// Send a request
    fn send(self: *Client, request: *const Request, uri: *const std.Uri) !Response {
        // Use Zig's built-in HTTP client for now
        // TODO: Replace with custom implementation using connection pool
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        var response_buf = std.ArrayList(u8){};
        errdefer response_buf.deinit(self.allocator);

        // Create writer interface - cast DeprecatedWriter to Writer
        var array_writer = response_buf.writer(self.allocator);
        var writer_deprecated = array_writer.any();
        const writer_ptr: *std.Io.Writer = @ptrCast(@alignCast(&writer_deprecated));

        const fetch_result = try client.fetch(.{
            .location = .{ .uri = uri.* },
            .method = @enumFromInt(@intFromEnum(request.method)),
            .response_writer = writer_ptr,
        });

        var response = Response.init(self.allocator, Status.fromCode(@intFromEnum(fetch_result.status)));
        try response.setBody(response_buf.items);

        return response;
    }

    fn applyDefaultHeaders(self: *Client, request: *Request) !void {
        var it = self.default_headers.iterator();
        while (it.next()) |entry| {
            if (!request.headers.contains(entry.key_ptr.*)) {
                try request.setHeader(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
};

/// Request builder for fluent API
pub const RequestBuilder = struct {
    client: *Client,
    request: Request,
    uri: std.Uri,

    pub fn init(client: *Client, method: Method, url: []const u8) !RequestBuilder {
        const uri = try std.Uri.parse(url);
        const request = try Request.init(client.allocator, method, uri.path.raw);

        return .{
            .client = client,
            .request = request,
            .uri = uri,
        };
    }

    pub fn deinit(self: *RequestBuilder) void {
        self.request.deinit();
    }

    pub fn header(self: *RequestBuilder, key: []const u8, value: []const u8) !*RequestBuilder {
        try self.request.setHeader(key, value);
        return self;
    }

    pub fn body(self: *RequestBuilder, data: []const u8) !*RequestBuilder {
        try self.request.setBody(data);
        return self;
    }

    pub fn json(self: *RequestBuilder, data: []const u8) !*RequestBuilder {
        try self.request.setJsonBody(data);
        return self;
    }

    pub fn send(self: *RequestBuilder) !Response {
        try self.client.applyDefaultHeaders(&self.request);
        if (self.uri.host) |host| {
            try self.request.setHeader("Host", host);
        }
        return try self.client.send(&self.request, &self.uri);
    }
};

test "Client creation and cleanup" {
    const allocator = std.testing.allocator;

    var client = Client.init(allocator);
    defer client.deinit();

    try client.setDefaultHeader("User-Agent", "PyAOT/1.0");
}

test "RequestBuilder fluent API" {
    const allocator = std.testing.allocator;

    var client = Client.init(allocator);
    defer client.deinit();

    var builder = try RequestBuilder.init(&client, .GET, "http://example.com/api");
    defer builder.deinit();

    _ = try builder.header("Accept", "application/json");

    // Note: Actual send() would require network, so we just test the builder pattern
}

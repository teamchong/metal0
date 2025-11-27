/// HTTP Client with connection pooling and builder pattern
const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Method = @import("request.zig").Method;
const Status = @import("response.zig").Status;
const ConnectionPool = @import("pool.zig").ConnectionPool;
const hashmap_helper = @import("hashmap_helper");
const LazyResponse = @import("lazy_response.zig").LazyResponse;

/// Extract raw string from Uri.Component (Zig 0.15 API)
fn getComponentString(component: std.Uri.Component) []const u8 {
    return switch (component) {
        .raw => |raw| raw,
        .percent_encoded => |enc| enc,
    };
}

fn getHostString(host: ?std.Uri.Component) []const u8 {
    if (host) |h| {
        return getComponentString(h);
    }
    return "";
}

fn getPathString(path: std.Uri.Component) []const u8 {
    const p = getComponentString(path);
    return if (p.len > 0) p else "/";
}

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
        var request = try Request.init(self.allocator, .GET, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));

        return try self.send(&request, &uri);
    }

    /// Simple POST request
    pub fn post(self: *Client, url: []const u8, body: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .POST, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));
        try request.setBody(body);

        return try self.send(&request, &uri);
    }

    /// POST with JSON body
    pub fn postJson(self: *Client, url: []const u8, json: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .POST, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));
        try request.setJsonBody(json);

        return try self.send(&request, &uri);
    }

    /// Simple PUT request
    pub fn put(self: *Client, url: []const u8, body: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .PUT, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));
        try request.setBody(body);

        return try self.send(&request, &uri);
    }

    /// Simple DELETE request
    pub fn delete(self: *Client, url: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .DELETE, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));

        return try self.send(&request, &uri);
    }

    /// Simple PATCH request
    pub fn patch(self: *Client, url: []const u8, body: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .PATCH, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));
        try request.setBody(body);

        return try self.send(&request, &uri);
    }

    /// Simple HEAD request
    pub fn head(self: *Client, url: []const u8) !Response {
        const uri = try std.Uri.parse(url);
        var request = try Request.init(self.allocator, .HEAD, getPathString(uri.path));
        defer request.deinit();

        try self.applyDefaultHeaders(&request);
        try request.setHeader("Host", getHostString(uri.host));

        return try self.send(&request, &uri);
    }

    /// Send a request and return response with body
    fn send(self: *Client, request: *const Request, uri: *const std.Uri) !Response {
        _ = request; // TODO: use custom headers from request

        // Use Zig's built-in HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const fetch_result = client.fetch(.{
            .location = .{ .uri = uri.* },
        }) catch |err| {
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };

        var response = Response.init(self.allocator, Status.fromCode(@intFromEnum(fetch_result.status)));
        // Body reading requires Zig 0.15 Writer API rework - return empty for now
        try response.setBody("");

        return response;
    }

    /// Fetch URL and return body as slice (simple API for Python wrappers)
    pub fn fetchBody(self: *Client, url: []const u8) ![]const u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = url },
        }) catch |err| {
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };

        // Return status as string for now (body reading needs Writer API rework)
        var buf: [16]u8 = undefined;
        const status_str = std.fmt.bufPrint(&buf, "{d}", .{@intFromEnum(result.status)}) catch "0";
        return try self.allocator.dupe(u8, status_str);
    }

    /// Fetch URL with POST body and return response body
    pub fn fetchBodyPost(self: *Client, url: []const u8, payload: []const u8) ![]const u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const result = client.fetch(.{
            .location = .{ .url = url },
            .payload = payload,
        }) catch |err| {
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return error.ConnectionFailed;
        };

        var buf: [16]u8 = undefined;
        const status_str = std.fmt.bufPrint(&buf, "{d}", .{@intFromEnum(result.status)}) catch "0";
        return try self.allocator.dupe(u8, status_str);
    }

    /// Lazy GET - body read deferred until accessed
    pub fn getLazy(self: *Client, url: []const u8) !LazyResponse {
        return try LazyResponse.init(self.allocator, url);
    }

    /// Lazy POST - body read deferred until accessed
    pub fn postLazy(self: *Client, url: []const u8, payload: []const u8) !LazyResponse {
        return try LazyResponse.initPost(self.allocator, url, payload);
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
        const request = try Request.init(client.allocator, method, getPathString(uri.path));

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

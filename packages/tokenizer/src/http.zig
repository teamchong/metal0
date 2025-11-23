/// PyAOT HTTP Module - Zero-copy client/server with connection pooling
const std = @import("std");
const runtime = @import("runtime.zig");

// Re-export core types
pub const Request = @import("http/request.zig").Request;
pub const Response = @import("http/response.zig").Response;
pub const Method = @import("http/request.zig").Method;
pub const Status = @import("http/response.zig").Status;
pub const Headers = @import("http/request.zig").Headers;

// Re-export client
pub const Client = @import("http/client.zig").Client;
pub const RequestBuilder = @import("http/client.zig").RequestBuilder;

// Re-export server
pub const Server = @import("http/server.zig").Server;
pub const ServerConfig = @import("http/server.zig").ServerConfig;

// Re-export router
pub const Router = @import("http/router.zig").Router;
pub const HandlerFn = @import("http/router.zig").HandlerFn;

// Re-export connection pool
pub const ConnectionPool = @import("http/pool.zig").ConnectionPool;

// Re-export async client
pub const AsyncClient = @import("http/async_client.zig").AsyncClient;
pub const AsyncClientError = @import("http/async_client.zig").AsyncClientError;

// Re-export middleware
pub const corsMiddleware = @import("http/server.zig").corsMiddleware;
pub const loggingMiddleware = @import("http/server.zig").loggingMiddleware;

/// Simple HTTP GET request
pub fn get(allocator: std.mem.Allocator, url: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();

    return try client.get(url);
}

/// Simple HTTP POST request
pub fn post(allocator: std.mem.Allocator, url: []const u8, body: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();

    return try client.post(url, body);
}

/// HTTP POST with JSON body
pub fn postJson(allocator: std.mem.Allocator, url: []const u8, json: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();

    return try client.postJson(url, json);
}

// Legacy compatibility functions for existing code
pub const HttpResponse = struct {
    status: u16,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HttpResponse) void {
        self.allocator.free(self.body);
    }
};

/// Create PyString from HTTP response body
pub fn getAsPyString(allocator: std.mem.Allocator, url: []const u8) !*runtime.PyObject {
    var response = try get(allocator, url);
    defer response.deinit();

    return try runtime.PyString.create(allocator, response.body);
}

/// Create PyTuple of (status_code, body)
pub fn getAsResponse(allocator: std.mem.Allocator, url: []const u8) !*runtime.PyObject {
    var response = try get(allocator, url);
    defer response.deinit();

    // Create tuple: (status, body)
    const status_obj = try runtime.PyInt.create(allocator, @intCast(response.statusCode()));
    const body_obj = try runtime.PyString.create(allocator, response.body);

    const items = [_]*runtime.PyObject{ status_obj, body_obj };
    return try runtime.PyTuple.create(allocator, &items);
}

// ===== Async HTTP API =====

const Future = @import("async.zig").Future;

/// Async GET request (returns Future)
pub fn asyncGet(allocator: std.mem.Allocator, poller: anytype, url: []const u8) !*Future(Response) {
    var client = AsyncClient.init(allocator, poller);
    return try client.get(url);
}

/// Async POST request (returns Future)
pub fn asyncPost(allocator: std.mem.Allocator, poller: anytype, url: []const u8, body: []const u8) !*Future(Response) {
    var client = AsyncClient.init(allocator, poller);
    return try client.post(url, body);
}

/// Async POST with JSON (returns Future)
pub fn asyncPostJson(allocator: std.mem.Allocator, poller: anytype, url: []const u8, json: []const u8) !*Future(Response) {
    var client = AsyncClient.init(allocator, poller);
    return try client.postJson(url, json);
}

/// Await async GET (convenience wrapper)
pub fn awaitGet(allocator: std.mem.Allocator, poller: anytype, url: []const u8, current_task: anytype) !Response {
    const future = try asyncGet(allocator, poller, url);
    return try future.await_future(current_task);
}

/// Await async POST (convenience wrapper)
pub fn awaitPost(allocator: std.mem.Allocator, poller: anytype, url: []const u8, body: []const u8, current_task: anytype) !Response {
    const future = try asyncPost(allocator, poller, url, body);
    return try future.await_future(current_task);
}

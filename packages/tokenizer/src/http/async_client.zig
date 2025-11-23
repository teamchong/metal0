/// Async HTTP client with non-blocking I/O
const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Method = @import("request.zig").Method;
const Status = @import("response.zig").Status;
const Future = @import("../async/future.zig").Future;
const Task = @import("../async/task.zig").Task;
const runtime = @import("../async/runtime.zig");
const Poller = @import("../async/poller/common.zig").Poller;
const common = @import("../async/poller/common.zig");

pub const AsyncClientError = error{
    InvalidUrl,
    ConnectionFailed,
    RequestFailed,
    ResponseParseFailed,
    Timeout,
    SocketError,
    ConnectError,
    WriteError,
    ReadError,
};

/// Async HTTP client
pub const AsyncClient = struct {
    allocator: std.mem.Allocator,
    poller: *Poller,
    timeout_ms: u64,
    default_headers: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator, poller: *Poller) AsyncClient {
        return .{
            .allocator = allocator,
            .poller = poller,
            .timeout_ms = 30000, // 30 second default timeout
            .default_headers = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncClient) void {
        var it = self.default_headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.default_headers.deinit();
    }

    /// Set default header for all requests
    pub fn setDefaultHeader(self: *AsyncClient, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        try self.default_headers.put(key_copy, value_copy);
    }

    /// Async GET request (returns Future)
    pub fn get(self: *AsyncClient, url: []const u8) !*Future(Response) {
        const future = try Future(Response).init(self.allocator);

        // Spawn async task
        const context = try self.allocator.create(RequestContext);
        context.* = .{
            .client = self,
            .future = future,
            .url = try self.allocator.dupe(u8, url),
            .method = .GET,
            .body = null,
        };

        _ = try runtime.spawn(self.allocator, fetchTask, context);

        return future;
    }

    /// Async POST request
    pub fn post(self: *AsyncClient, url: []const u8, body: []const u8) !*Future(Response) {
        const future = try Future(Response).init(self.allocator);

        const context = try self.allocator.create(RequestContext);
        context.* = .{
            .client = self,
            .future = future,
            .url = try self.allocator.dupe(u8, url),
            .method = .POST,
            .body = try self.allocator.dupe(u8, body),
        };

        _ = try runtime.spawn(self.allocator, fetchTask, context);

        return future;
    }

    /// Async POST with JSON body
    pub fn postJson(self: *AsyncClient, url: []const u8, json: []const u8) !*Future(Response) {
        const future = try Future(Response).init(self.allocator);

        const context = try self.allocator.create(RequestContext);
        context.* = .{
            .client = self,
            .future = future,
            .url = try self.allocator.dupe(u8, url),
            .method = .POST,
            .body = try self.allocator.dupe(u8, json),
            .is_json = true,
        };

        _ = try runtime.spawn(self.allocator, fetchTask, context);

        return future;
    }
};

/// Request context for async task
const RequestContext = struct {
    client: *AsyncClient,
    future: *Future(Response),
    url: []const u8,
    method: Method,
    body: ?[]const u8,
    is_json: bool = false,
};

/// Async fetch task (runs in background)
fn fetchTask(context_ptr: *anyopaque) anyerror!void {
    const context: *RequestContext = @ptrCast(@alignCast(context_ptr));
    defer {
        context.client.allocator.free(context.url);
        if (context.body) |body| {
            context.client.allocator.free(body);
        }
        context.client.allocator.destroy(context);
    }

    // Parse URL
    const uri = std.Uri.parse(context.url) catch {
        context.future.reject(AsyncClientError.InvalidUrl);
        return;
    };

    // Create socket
    const sock = std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM | std.posix.SOCK.NONBLOCK,
        0,
    ) catch {
        context.future.reject(AsyncClientError.SocketError);
        return;
    };
    defer std.posix.close(sock);

    // Get current task (for I/O blocking)
    // NOTE: This will be provided by runtime context in full implementation
    // For now, we'll use a simplified approach

    // Async connect
    asyncConnect(sock, &uri) catch |err| {
        context.future.reject(err);
        return;
    };

    // Build and send request
    const request = buildRequest(context, &uri) catch |err| {
        context.future.reject(err);
        return;
    };
    defer context.client.allocator.free(request);

    asyncWrite(sock, request) catch |err| {
        context.future.reject(err);
        return;
    };

    // Receive response
    var buf: [65536]u8 = undefined;
    const n = asyncRead(sock, &buf) catch |err| {
        context.future.reject(err);
        return;
    };

    // Parse response
    const response = parseResponse(buf[0..n], context.client.allocator) catch |err| {
        context.future.reject(err);
        return;
    };

    context.future.resolve(response);
}

/// Async connect (non-blocking)
fn asyncConnect(sock: std.posix.fd_t, uri: *const std.Uri) !void {
    // Resolve address
    const addr = try resolveAddress(uri.host orelse return error.InvalidUrl);

    // Non-blocking connect
    const result = std.posix.connect(sock, &addr.any, addr.getOsSockLen());

    if (result) {
        return; // Connected immediately
    } else |err| {
        if (err == error.WouldBlock) {
            // For now, just sleep and retry (simplified)
            // In full implementation, this would register with poller and yield
            std.time.sleep(10_000_000); // 10ms

            // Check if connect succeeded
            var err_code: i32 = undefined;
            var err_len: u32 = @sizeOf(i32);
            _ = std.c.getsockopt(
                sock,
                std.posix.SOL.SOCKET,
                std.posix.SO.ERROR,
                @ptrCast(&err_code),
                &err_len,
            );

            if (err_code != 0) {
                return error.ConnectFailed;
            }
            return;
        }
        return err;
    }
}

/// Async write (non-blocking)
fn asyncWrite(sock: std.posix.fd_t, data: []const u8) !usize {
    var written: usize = 0;
    var retries: u32 = 0;

    while (written < data.len and retries < 100) {
        const result = std.posix.write(sock, data[written..]);

        if (result) |n| {
            written += n;
        } else |err| {
            if (err == error.WouldBlock) {
                // Simplified: sleep and retry
                // Full implementation would register with poller and yield
                std.time.sleep(1_000_000); // 1ms
                retries += 1;
            } else {
                return err;
            }
        }
    }

    if (written < data.len) {
        return error.WriteError;
    }

    return written;
}

/// Async read (non-blocking)
fn asyncRead(sock: std.posix.fd_t, buffer: []u8) !usize {
    var retries: u32 = 0;

    while (retries < 100) {
        const result = std.posix.read(sock, buffer);

        if (result) |n| {
            return n;
        } else |err| {
            if (err == error.WouldBlock) {
                // Simplified: sleep and retry
                // Full implementation would register with poller and yield
                std.time.sleep(1_000_000); // 1ms
                retries += 1;
            } else {
                return err;
            }
        }
    }

    return error.ReadError;
}

/// Resolve hostname to address
fn resolveAddress(host: []const u8) !std.net.Address {
    // For now, only support IP addresses
    // Full DNS resolution would be added later

    // Try to parse as IP address
    const port: u16 = 80; // Default HTTP port

    if (std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1")) {
        return std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);
    }

    // Try to parse IPv4
    if (std.net.Address.parseIp4(host, port)) |addr| {
        return addr;
    } else |_| {}

    // For testing, use a simple DNS lookup
    const list = try std.net.getAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();

    if (list.addrs.len == 0) {
        return error.InvalidUrl;
    }

    return list.addrs[0];
}

/// Build HTTP request string
fn buildRequest(context: *const RequestContext, uri: *const std.Uri) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(context.client.allocator);

    const writer = buf.writer(context.client.allocator);

    // Request line
    const method_str = switch (context.method) {
        .GET => "GET",
        .POST => "POST",
        .PUT => "PUT",
        .DELETE => "DELETE",
        .HEAD => "HEAD",
        .OPTIONS => "OPTIONS",
        .PATCH => "PATCH",
    };

    const path = if (uri.path.raw.len > 0) uri.path.raw else "/";
    try writer.print("{s} {s} HTTP/1.1\r\n", .{ method_str, path });

    // Host header
    try writer.print("Host: {s}\r\n", .{uri.host orelse ""});

    // Default headers
    var it = context.client.default_headers.iterator();
    while (it.next()) |entry| {
        try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    // Content headers for POST
    if (context.body) |body| {
        if (context.is_json) {
            try writer.writeAll("Content-Type: application/json\r\n");
        }
        try writer.print("Content-Length: {d}\r\n", .{body.len});
    }

    // End headers
    try writer.writeAll("\r\n");

    // Body
    if (context.body) |body| {
        try writer.writeAll(body);
    }

    return try buf.toOwnedSlice(context.client.allocator);
}

/// Parse HTTP response
fn parseResponse(data: []const u8, allocator: std.mem.Allocator) !Response {
    // Find headers/body split
    const split = std.mem.indexOf(u8, data, "\r\n\r\n") orelse return error.ResponseParseFailed;

    const headers_data = data[0..split];
    const body_data = data[split + 4 ..];

    // Parse status line
    var lines = std.mem.splitScalar(u8, headers_data, '\n');
    const status_line = lines.next() orelse return error.ResponseParseFailed;

    // Extract status code (format: "HTTP/1.1 200 OK")
    var status_parts = std.mem.splitScalar(u8, status_line, ' ');
    _ = status_parts.next(); // Skip "HTTP/1.1"
    const status_str = status_parts.next() orelse return error.ResponseParseFailed;
    const status_code = std.fmt.parseInt(u16, status_str, 10) catch return error.ResponseParseFailed;

    // Create response
    var response = Response.init(allocator, Status.fromCode(status_code));

    // Parse headers
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0) continue;

        const colon = std.mem.indexOf(u8, trimmed, ":") orelse continue;
        const key = std.mem.trim(u8, trimmed[0..colon], " ");
        const value = std.mem.trim(u8, trimmed[colon + 1 ..], " ");

        try response.setHeader(key, value);
    }

    // Set body
    try response.setBody(body_data);

    return response;
}

test "AsyncClient creation and cleanup" {
    const allocator = std.testing.allocator;

    var poller = try Poller.init(allocator);
    defer poller.deinit();

    var client = AsyncClient.init(allocator, &poller);
    defer client.deinit();

    try client.setDefaultHeader("User-Agent", "PyAOT/1.0");
}

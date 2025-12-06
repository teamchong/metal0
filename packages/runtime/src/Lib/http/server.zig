/// HTTP Server with routing and middleware support
const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Router = @import("router.zig").Router;
const HandlerFn = @import("router.zig").HandlerFn;
const Method = @import("request.zig").Method;
const Status = @import("response.zig").Status;

pub const ServerError = error{
    BindFailed,
    AcceptFailed,
    ReadFailed,
    WriteFailed,
};

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8000,
    max_connections: usize = 1000,
    read_timeout_ms: u64 = 5000,
    write_timeout_ms: u64 = 5000,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    router: Router,
    config: ServerConfig,
    listener: ?std.net.Server = null,

    pub fn init(allocator: std.mem.Allocator) Server {
        return .{
            .allocator = allocator,
            .router = Router.init(allocator),
            .config = .{},
        };
    }

    pub fn deinit(self: *Server) void {
        if (self.listener) |*listener| {
            listener.deinit();
        }
        self.router.deinit();
    }

    /// Configure server settings
    pub fn configure(self: *Server, config: ServerConfig) void {
        self.config = config;
    }

    /// Add route handlers
    pub fn get(self: *Server, path: []const u8, handler: HandlerFn) !void {
        try self.router.get(path, handler);
    }

    pub fn post(self: *Server, path: []const u8, handler: HandlerFn) !void {
        try self.router.post(path, handler);
    }

    pub fn put(self: *Server, path: []const u8, handler: HandlerFn) !void {
        try self.router.put(path, handler);
    }

    pub fn delete(self: *Server, path: []const u8, handler: HandlerFn) !void {
        try self.router.delete(path, handler);
    }

    pub fn patch(self: *Server, path: []const u8, handler: HandlerFn) !void {
        try self.router.patch(path, handler);
    }

    /// Start server and listen for connections
    pub fn listen(self: *Server) !void {
        const address = try std.net.Address.parseIp(self.config.host, self.config.port);

        var listener = try address.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        });
        self.listener = listener;

        std.debug.print("Server listening on {s}:{d}\n", .{ self.config.host, self.config.port });

        while (true) {
            const connection = try listener.accept();
            try self.handleConnection(connection);
        }
    }

    /// Start server in background (non-blocking)
    pub fn listenAsync(self: *Server) !std.Thread {
        return try std.Thread.spawn(.{}, listenThread, .{self});
    }

    fn listenThread(self: *Server) !void {
        try self.listen();
    }

    /// Handle single client connection
    fn handleConnection(self: *Server, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        var buf: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buf);

        if (bytes_read == 0) return;

        const request_data = buf[0..bytes_read];

        // Parse request
        var request = Request.parse(self.allocator, request_data) catch |err| {
            std.debug.print("Failed to parse request: {}\n", .{err});
            return self.sendErrorResponse(connection.stream, .bad_request);
        };
        defer request.deinit();

        // Route and handle request
        var response = self.router.handle(&request) catch |err| {
            std.debug.print("Handler error: {}\n", .{err});
            return self.sendErrorResponse(connection.stream, .internal_server_error);
        };
        defer response.deinit();

        // Send response
        try self.sendResponse(connection.stream, &response);
    }

    fn sendResponse(self: *Server, stream: std.net.Stream, response: *const Response) !void {
        const data = try response.serialize(self.allocator);
        defer self.allocator.free(data);

        _ = try stream.write(data);
    }

    fn sendErrorResponse(self: *Server, stream: std.net.Stream, status: Status) !void {
        var response = Response.init(self.allocator, status);
        defer response.deinit();

        try response.setTextBody(status.reason());
        try self.sendResponse(stream, &response);
    }

    /// Graceful shutdown
    pub fn shutdown(self: *Server) void {
        if (self.listener) |*listener| {
            listener.deinit();
            self.listener = null;
        }
    }
};

/// Middleware function type
pub const MiddlewareFn = *const fn (allocator: std.mem.Allocator, request: *Request, next: HandlerFn) anyerror!Response;

/// CORS middleware
pub fn corsMiddleware(allocator: std.mem.Allocator, request: *Request, next: HandlerFn) !Response {
    var response = try next(allocator, request);

    try response.setHeader("Access-Control-Allow-Origin", "*");
    try response.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    try response.setHeader("Access-Control-Allow-Headers", "Content-Type");

    return response;
}

/// Logging middleware
pub fn loggingMiddleware(allocator: std.mem.Allocator, request: *Request, next: HandlerFn) !Response {
    const start = std.time.milliTimestamp();

    var response = try next(allocator, request);

    const duration = std.time.milliTimestamp() - start;
    std.debug.print("{s} {s} - {d} ({d}ms)\n", .{
        request.method.toString(),
        request.path,
        response.statusCode(),
        duration,
    });

    return response;
}

test "Server creation and configuration" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator);
    defer server.deinit();

    server.configure(.{
        .host = "0.0.0.0",
        .port = 3000,
    });

    try std.testing.expectEqualStrings("0.0.0.0", server.config.host);
    try std.testing.expectEqual(@as(u16, 3000), server.config.port);
}

test "Server route registration" {
    const allocator = std.testing.allocator;

    var server = Server.init(allocator);
    defer server.deinit();

    const handler = struct {
        fn handle(alloc: std.mem.Allocator, req: *const Request) !Response {
            _ = req;
            var resp = Response.init(alloc, .ok);
            try resp.setTextBody("test");
            return resp;
        }
    }.handle;

    try server.get("/test", handler);

    const route = server.router.findRoute(.GET, "/test");
    try std.testing.expect(route != null);
}

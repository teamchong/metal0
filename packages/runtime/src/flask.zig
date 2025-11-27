const std = @import("std");

/// Flask application - minimal implementation for AOT compilation
pub const Flask = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    routes: std.StringHashMap(RouteHandler),

    const RouteHandler = struct {
        handler: *const fn () []const u8,
        methods: []const []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*Flask {
        const app = try allocator.create(Flask);
        app.* = Flask{
            .allocator = allocator,
            .name = name,
            .routes = std.StringHashMap(RouteHandler).init(allocator),
        };
        return app;
    }

    pub fn deinit(self: *Flask) void {
        self.routes.deinit();
        self.allocator.destroy(self);
    }

    /// Route decorator - called as app.route("/path")(handler)
    /// Returns a RouteDecorator that can be called with the handler
    pub fn route(self: *Flask, path: []const u8) RouteDecorator {
        return RouteDecorator{ .app = self, .path = path };
    }

    /// Run the Flask development server
    pub fn run(self: *Flask, options: struct {
        host: []const u8 = "127.0.0.1",
        port: u16 = 5000,
        debug: bool = false,
    }) !void {
        std.debug.print(" * Running on http://{s}:{d}\n", .{ options.host, options.port });
        std.debug.print(" * Debug mode: {s}\n", .{if (options.debug) "on" else "off"});

        // Start HTTP server
        const address = try std.net.Address.parseIp(options.host, options.port);
        var server = try address.listen(.{});
        defer server.deinit();

        while (true) {
            var connection = try server.accept();
            defer connection.stream.close();

            // Read request
            var buf: [4096]u8 = undefined;
            const n = try connection.stream.read(&buf);
            if (n == 0) continue;

            const request = buf[0..n];

            // Parse path from request
            const path = parseRequestPath(request);

            // Find handler
            if (self.routes.get(path)) |handler| {
                const response = handler.handler();
                const http_response = std.fmt.allocPrint(self.allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {d}\r\n\r\n{s}", .{ response.len, response }) catch continue;
                defer self.allocator.free(http_response);
                _ = connection.stream.write(http_response) catch {};
            } else {
                const not_found = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
                _ = connection.stream.write(not_found) catch {};
            }
        }
    }

    fn parseRequestPath(request: []const u8) []const u8 {
        // Parse "GET /path HTTP/1.1"
        var iter = std.mem.splitScalar(u8, request, ' ');
        _ = iter.next(); // Skip method
        return iter.next() orelse "/";
    }
};

/// Route decorator - intermediate object returned by app.route("/path")
pub const RouteDecorator = struct {
    app: *Flask,
    path: []const u8,

    /// Called as decorator(handler) to register the route
    pub fn call(self: RouteDecorator, handler: *const fn () []const u8) void {
        self.app.routes.put(self.path, Flask.RouteHandler{
            .handler = handler,
            .methods = &[_][]const u8{"GET"},
        }) catch {};
    }
};

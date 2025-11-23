/// HTTP router with pattern matching
const std = @import("std");
const Request = @import("request.zig").Request;
const Response = @import("response.zig").Response;
const Method = @import("request.zig").Method;
const Status = @import("response.zig").Status;

pub const HandlerFn = *const fn (allocator: std.mem.Allocator, request: *const Request) anyerror!Response;

pub const Route = struct {
    method: Method,
    path: []const u8,
    handler: HandlerFn,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, method: Method, path: []const u8, handler: HandlerFn) !Route {
        const path_copy = try allocator.dupe(u8, path);
        return .{
            .method = method,
            .path = path_copy,
            .handler = handler,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Route) void {
        self.allocator.free(self.path);
    }

    pub fn matches(self: *const Route, method: Method, path: []const u8) bool {
        if (self.method != method) return false;
        return self.matchesPath(path);
    }

    fn matchesPath(self: *const Route, path: []const u8) bool {
        // Exact match
        if (std.mem.eql(u8, self.path, path)) return true;

        // Pattern matching (e.g., /users/:id)
        return self.matchesPattern(path);
    }

    fn matchesPattern(self: *const Route, path: []const u8) bool {
        var route_parts = std.mem.splitScalar(u8, self.path, '/');
        var path_parts = std.mem.splitScalar(u8, path, '/');

        while (true) {
            const route_part = route_parts.next();
            const path_part = path_parts.next();

            if (route_part == null and path_part == null) return true;
            if (route_part == null or path_part == null) return false;

            const r = route_part.?;
            const p = path_part.?;

            // Dynamic segment (e.g., :id, :name)
            if (r.len > 0 and r[0] == ':') continue;

            // Exact match
            if (!std.mem.eql(u8, r, p)) return false;
        }
    }
};

pub const Router = struct {
    routes: std.ArrayList(Route),
    allocator: std.mem.Allocator,
    not_found_handler: ?HandlerFn,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .routes = std.ArrayList(Route).init(allocator),
            .allocator = allocator,
            .not_found_handler = null,
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |*route| {
            route.deinit();
        }
        self.routes.deinit(self.allocator);
    }

    /// Add a route
    pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: HandlerFn) !void {
        const route = try Route.init(self.allocator, method, path, handler);
        try self.routes.append(self.allocator, route);
    }

    /// Convenience methods for HTTP methods
    pub fn get(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(.GET, path, handler);
    }

    pub fn post(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(.POST, path, handler);
    }

    pub fn put(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(.PUT, path, handler);
    }

    pub fn delete(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(.DELETE, path, handler);
    }

    pub fn patch(self: *Router, path: []const u8, handler: HandlerFn) !void {
        try self.addRoute(.PATCH, path, handler);
    }

    /// Set custom 404 handler
    pub fn setNotFoundHandler(self: *Router, handler: HandlerFn) void {
        self.not_found_handler = handler;
    }

    /// Find matching route for request
    pub fn findRoute(self: *const Router, method: Method, path: []const u8) ?*const Route {
        for (self.routes.items) |*route| {
            if (route.matches(method, path)) {
                return route;
            }
        }
        return null;
    }

    /// Handle request and generate response
    pub fn handle(self: *const Router, request: *const Request) !Response {
        if (self.findRoute(request.method, request.path)) |route| {
            return try route.handler(self.allocator, request);
        }

        // 404 Not Found
        if (self.not_found_handler) |handler| {
            return try handler(self.allocator, request);
        }

        var response = Response.init(self.allocator, .not_found);
        try response.setTextBody("404 Not Found");
        return response;
    }

    /// Extract path parameters from request
    pub fn extractParams(_: *const Router, route_path: []const u8, request_path: []const u8, allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
        var params = std.StringHashMap([]const u8).init(allocator);
        errdefer params.deinit();

        var route_parts = std.mem.splitScalar(u8, route_path, '/');
        var path_parts = std.mem.splitScalar(u8, request_path, '/');

        while (true) {
            const route_part = route_parts.next();
            const path_part = path_parts.next();

            if (route_part == null or path_part == null) break;

            const r = route_part.?;
            const p = path_part.?;

            // Dynamic segment
            if (r.len > 0 and r[0] == ':') {
                const param_name = r[1..];
                const param_value = try allocator.dupe(u8, p);
                const param_name_copy = try allocator.dupe(u8, param_name);
                try params.put(param_name_copy, param_value);
            }
        }

        return params;
    }
};

// Example handlers for testing
fn helloHandler(allocator: std.mem.Allocator, request: *const Request) !Response {
    _ = request;
    var response = Response.init(allocator, .ok);
    try response.setTextBody("Hello, World!");
    return response;
}

fn echoHandler(allocator: std.mem.Allocator, request: *const Request) !Response {
    var response = Response.init(allocator, .ok);
    try response.setBody(request.body);
    return response;
}

test "Router basic routing" {
    const allocator = std.testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", helloHandler);
    try router.post("/echo", echoHandler);

    const route1 = router.findRoute(.GET, "/hello");
    try std.testing.expect(route1 != null);

    const route2 = router.findRoute(.POST, "/echo");
    try std.testing.expect(route2 != null);

    const route3 = router.findRoute(.GET, "/notfound");
    try std.testing.expect(route3 == null);
}

test "Router pattern matching" {
    const allocator = std.testing.allocator;

    var route = try Route.init(allocator, .GET, "/users/:id", helloHandler);
    defer route.deinit();

    try std.testing.expect(route.matches(.GET, "/users/123"));
    try std.testing.expect(route.matches(.GET, "/users/abc"));
    try std.testing.expect(!route.matches(.GET, "/users"));
    try std.testing.expect(!route.matches(.POST, "/users/123"));
}

test "Router extract params" {
    const allocator = std.testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var params = try router.extractParams("/users/:id/posts/:post_id", "/users/123/posts/456", allocator);
    defer {
        var it = params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        params.deinit();
    }

    try std.testing.expectEqualStrings("123", params.get("id").?);
    try std.testing.expectEqualStrings("456", params.get("post_id").?);
}

test "Router handle request" {
    const allocator = std.testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    try router.get("/hello", helloHandler);

    var request = try Request.init(allocator, .GET, "/hello");
    defer request.deinit();

    var response = try router.handle(&request);
    defer response.deinit();

    try std.testing.expectEqual(Status.ok, response.status);
    try std.testing.expectEqualStrings("Hello, World!", response.body);
}

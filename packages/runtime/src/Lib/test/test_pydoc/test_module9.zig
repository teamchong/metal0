//! test.test_pydoc.test_server - Tests for pydoc HTTP server
//! Tests the built-in documentation server functionality.

const std = @import("std");
const testing = std.testing;

/// Server configuration
pub const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 0,
    browser_open: bool = true,
    cache_ttl: u32 = 3600,
    theme: Theme = .light,

    pub const Theme = enum {
        light,
        dark,
        system,
    };

    pub const default = ServerConfig{};

    pub fn withPort(self: ServerConfig, port: u16) ServerConfig {
        var result = self;
        result.port = port;
        return result;
    }

    pub fn withHost(self: ServerConfig, host: []const u8) ServerConfig {
        var result = self;
        result.host = host;
        return result;
    }

    pub fn withTheme(self: ServerConfig, theme: Theme) ServerConfig {
        var result = self;
        result.theme = theme;
        return result;
    }

    pub fn noBrowser(self: ServerConfig) ServerConfig {
        var result = self;
        result.browser_open = false;
        return result;
    }
};

/// Request types
pub const RequestType = enum {
    index,
    module,
    class_type,
    function,
    search,
    static,
    topics,
    keywords,

    pub fn fromPath(path: []const u8) RequestType {
        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            return .index;
        }
        if (std.mem.startsWith(u8, path, "/search")) {
            return .search;
        }
        if (std.mem.startsWith(u8, path, "/static/")) {
            return .static;
        }
        if (std.mem.startsWith(u8, path, "/topics")) {
            return .topics;
        }
        if (std.mem.startsWith(u8, path, "/keywords")) {
            return .keywords;
        }
        return .module;
    }
};

/// HTTP request representation
pub const Request = struct {
    method: Method,
    path: []const u8,
    query: ?[]const u8,
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub const Method = enum {
        GET,
        POST,
        HEAD,
        OPTIONS,
    };

    pub fn init(allocator: std.mem.Allocator, method: Method, path: []const u8) Request {
        return .{
            .method = method,
            .path = path,
            .query = null,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }

    pub fn getHeader(self: Request, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn requestType(self: Request) RequestType {
        return RequestType.fromPath(self.path);
    }

    pub fn getQueryParam(self: Request, name: []const u8) ?[]const u8 {
        if (self.query) |q| {
            var params = std.mem.splitScalar(u8, q, '&');
            while (params.next()) |param| {
                var kv = std.mem.splitScalar(u8, param, '=');
                const key = kv.first();
                if (std.mem.eql(u8, key, name)) {
                    return kv.rest();
                }
            }
        }
        return null;
    }
};

/// HTTP response representation
pub const Response = struct {
    status: u16 = 200,
    content_type: []const u8 = "text/html; charset=utf-8",
    body: std.ArrayList(u8),
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Response {
        return .{
            .body = std.ArrayList(u8).init(allocator),
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Response) void {
        self.body.deinit();
        self.headers.deinit();
    }

    pub fn setStatus(self: *Response, status: u16) void {
        self.status = status;
    }

    pub fn setContentType(self: *Response, ct: []const u8) void {
        self.content_type = ct;
    }

    pub fn write(self: *Response, data: []const u8) !void {
        try self.body.appendSlice(data);
    }

    pub fn setHeader(self: *Response, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    pub fn redirect(self: *Response, location: []const u8) !void {
        self.status = 302;
        try self.setHeader("Location", location);
    }

    pub fn statusText(self: Response) []const u8 {
        return switch (self.status) {
            200 => "OK",
            301 => "Moved Permanently",
            302 => "Found",
            400 => "Bad Request",
            404 => "Not Found",
            500 => "Internal Server Error",
            else => "Unknown",
        };
    }
};

/// Route handler
pub const RouteHandler = struct {
    pattern: []const u8,
    handler_fn: *const fn (*Request, *Response) anyerror!void,

    pub fn handle(self: RouteHandler, req: *Request, res: *Response) !void {
        try self.handler_fn(req, res);
    }
};

/// Documentation server
pub const DocServer = struct {
    config: ServerConfig,
    routes: std.ArrayList(RouteHandler),
    running: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) DocServer {
        return .{
            .config = config,
            .routes = std.ArrayList(RouteHandler).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DocServer) void {
        self.routes.deinit();
    }

    pub fn addRoute(self: *DocServer, pattern: []const u8, handler: *const fn (*Request, *Response) anyerror!void) !void {
        try self.routes.append(.{ .pattern = pattern, .handler_fn = handler });
    }

    pub fn start(self: *DocServer) !void {
        self.running = true;
    }

    pub fn stop(self: *DocServer) void {
        self.running = false;
    }

    pub fn isRunning(self: DocServer) bool {
        return self.running;
    }

    pub fn getUrl(self: DocServer) []const u8 {
        _ = self;
        return "http://localhost:0/";
    }

    pub fn routeCount(self: DocServer) usize {
        return self.routes.items.len;
    }
};

/// Static file handler
pub const StaticHandler = struct {
    root_path: []const u8,
    extensions: []const []const u8,

    pub const default_extensions = &[_][]const u8{ ".html", ".css", ".js", ".png", ".ico" };

    pub fn init(root_path: []const u8) StaticHandler {
        return .{
            .root_path = root_path,
            .extensions = default_extensions,
        };
    }

    pub fn getMimeType(self: StaticHandler, path: []const u8) []const u8 {
        _ = self;
        if (std.mem.endsWith(u8, path, ".html")) return "text/html";
        if (std.mem.endsWith(u8, path, ".css")) return "text/css";
        if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
        if (std.mem.endsWith(u8, path, ".png")) return "image/png";
        if (std.mem.endsWith(u8, path, ".ico")) return "image/x-icon";
        return "application/octet-stream";
    }

    pub fn isAllowed(self: StaticHandler, path: []const u8) bool {
        for (self.extensions) |ext| {
            if (std.mem.endsWith(u8, path, ext)) return true;
        }
        return false;
    }
};

/// URL builder for documentation links
pub const UrlBuilder = struct {
    base_url: []const u8,

    pub fn init(base_url: []const u8) UrlBuilder {
        return .{ .base_url = base_url };
    }

    pub fn module(self: UrlBuilder, allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/module/{s}", .{ self.base_url, name });
    }

    pub fn search(self: UrlBuilder, allocator: std.mem.Allocator, query: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/search?q={s}", .{ self.base_url, query });
    }
};

// Tests
test "server_config_defaults" {
    const config = ServerConfig.default;
    try testing.expectEqualStrings("localhost", config.host);
    try testing.expect(config.browser_open);
}

test "server_config_with_port" {
    const config = ServerConfig.default.withPort(8080);
    try testing.expectEqual(@as(u16, 8080), config.port);
}

test "server_config_no_browser" {
    const config = ServerConfig.default.noBrowser();
    try testing.expect(!config.browser_open);
}

test "request_type_from_path_index" {
    try testing.expectEqual(RequestType.index, RequestType.fromPath("/"));
    try testing.expectEqual(RequestType.index, RequestType.fromPath("/index.html"));
}

test "request_type_from_path_search" {
    try testing.expectEqual(RequestType.search, RequestType.fromPath("/search?q=test"));
}

test "request_type_from_path_module" {
    try testing.expectEqual(RequestType.module, RequestType.fromPath("/os"));
}

test "request_init" {
    var req = Request.init(testing.allocator, .GET, "/test");
    defer req.deinit();
    try testing.expectEqual(Request.Method.GET, req.method);
    try testing.expectEqualStrings("/test", req.path);
}

test "request_type" {
    var req = Request.init(testing.allocator, .GET, "/");
    defer req.deinit();
    try testing.expectEqual(RequestType.index, req.requestType());
}

test "response_init" {
    var res = Response.init(testing.allocator);
    defer res.deinit();
    try testing.expectEqual(@as(u16, 200), res.status);
}

test "response_set_status" {
    var res = Response.init(testing.allocator);
    defer res.deinit();
    res.setStatus(404);
    try testing.expectEqual(@as(u16, 404), res.status);
}

test "response_write" {
    var res = Response.init(testing.allocator);
    defer res.deinit();
    try res.write("Hello");
    try testing.expectEqualStrings("Hello", res.body.items);
}

test "response_status_text" {
    var res = Response.init(testing.allocator);
    defer res.deinit();
    try testing.expectEqualStrings("OK", res.statusText());
    res.setStatus(404);
    try testing.expectEqualStrings("Not Found", res.statusText());
}

test "doc_server_init" {
    var server = DocServer.init(testing.allocator, ServerConfig.default);
    defer server.deinit();
    try testing.expect(!server.isRunning());
}

test "doc_server_start_stop" {
    var server = DocServer.init(testing.allocator, ServerConfig.default);
    defer server.deinit();
    try server.start();
    try testing.expect(server.isRunning());
    server.stop();
    try testing.expect(!server.isRunning());
}

test "static_handler_mime_type" {
    const handler = StaticHandler.init("/static");
    try testing.expectEqualStrings("text/html", handler.getMimeType("page.html"));
    try testing.expectEqualStrings("text/css", handler.getMimeType("style.css"));
    try testing.expectEqualStrings("application/javascript", handler.getMimeType("app.js"));
}

test "static_handler_is_allowed" {
    const handler = StaticHandler.init("/static");
    try testing.expect(handler.isAllowed("page.html"));
    try testing.expect(handler.isAllowed("style.css"));
    try testing.expect(!handler.isAllowed("script.py"));
}

test "url_builder_module" {
    const builder = UrlBuilder.init("http://localhost:8080");
    const url = try builder.module(testing.allocator, "os");
    defer testing.allocator.free(url);
    try testing.expectEqualStrings("http://localhost:8080/module/os", url);
}

test "url_builder_search" {
    const builder = UrlBuilder.init("http://localhost:8080");
    const url = try builder.search(testing.allocator, "print");
    defer testing.allocator.free(url);
    try testing.expectEqualStrings("http://localhost:8080/search?q=print", url);
}

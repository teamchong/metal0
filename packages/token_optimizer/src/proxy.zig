const std = @import("std");
const compress = @import("compress.zig");
const Server = @import("../../runtime/src/http/server.zig").Server;
const ServerConfig = @import("../../runtime/src/http/server.zig").ServerConfig;
const Client = @import("../../runtime/src/http/client.zig").Client;
const Request = @import("../../runtime/src/http/request.zig").Request;
const Response = @import("../../runtime/src/http/response.zig").Response;

pub const ProxyServer = struct {
    allocator: std.mem.Allocator,
    compressor: compress.TextCompressor,
    server: Server,
    client: Client,

    pub fn init(allocator: std.mem.Allocator) ProxyServer {
        return ProxyServer{
            .allocator = allocator,
            .compressor = compress.TextCompressor.init(allocator),
            .server = Server.init(allocator),
            .client = Client.init(allocator),
        };
    }

    pub fn deinit(self: *ProxyServer) void {
        self.server.deinit();
        self.client.deinit();
    }

    pub fn listen(self: *ProxyServer, port: u16) !void {
        self.server.configure(.{
            .host = "127.0.0.1",
            .port = port,
        });

        // Register catch-all route to proxy all requests
        try self.server.router.any("/*", proxyHandler, self);

        std.debug.print("Proxy listening on http://127.0.0.1:{d}\n", .{port});
        try self.server.listen();
    }

    fn proxyHandler(ctx: *anyopaque, request: *Request, response: *Response) !void {
        const self: *ProxyServer = @ptrCast(@alignCast(ctx));

        std.debug.print("\n=== INCOMING REQUEST ===\n", .{});
        std.debug.print("Method: {s}\n", .{request.method.toString()});
        std.debug.print("Path: {s}\n", .{request.path});

        // Get request body
        const body = request.body orelse &[_]u8{};
        std.debug.print("Body size: {d} bytes\n", .{body.len});

        // Compress request (convert text to images)
        const compressed_body = if (body.len > 0)
            try self.compressor.compressRequest(body)
        else
            try self.allocator.dupe(u8, body);
        defer self.allocator.free(compressed_body);

        std.debug.print("Compression: {d} bytes → {d} bytes", .{ body.len, compressed_body.len });
        if (body.len > 0) {
            const savings = @as(f64, @floatFromInt(body.len - compressed_body.len)) / @as(f64, @floatFromInt(body.len)) * 100.0;
            std.debug.print(" ({d:.1}% savings)", .{savings});
        }
        std.debug.print("\n", .{});

        // Forward to Anthropic API
        std.debug.print("\n=== FORWARDING TO ANTHROPIC ===\n", .{});
        const uri_str = try std.fmt.allocPrint(self.allocator, "https://api.anthropic.com{s}", .{request.path});
        defer self.allocator.free(uri_str);
        std.debug.print("Target: {s}\n", .{uri_str});

        // Create forwarding request
        const uri = try std.Uri.parse(uri_str);
        var forward_req = try Request.init(self.allocator, request.method, uri.path.raw);
        defer forward_req.deinit();

        // Copy headers from original request
        var it = request.headers.map.iterator();
        while (it.next()) |entry| {
            try forward_req.setHeader(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Set host header
        try forward_req.setHeader("Host", uri.host orelse "api.anthropic.com");

        // Set compressed body
        try forward_req.setBody(compressed_body);

        std.debug.print("Forwarding {d} headers\n", .{forward_req.headers.map.count()});
        std.debug.print("Body size: {d} bytes\n", .{compressed_body.len});

        // Send request to Anthropic
        var api_response = try self.client.send(&forward_req, &uri);
        defer api_response.deinit();

        std.debug.print("\n=== RECEIVING RESPONSE ===\n", .{});
        std.debug.print("Status: {d}\n", .{@intFromEnum(api_response.status)});
        std.debug.print("Response body size: {d} bytes\n", .{api_response.body.len});

        // Send response back to client
        std.debug.print("\n=== SENDING TO CLIENT ===\n", .{});
        std.debug.print("Status: {d}\n", .{@intFromEnum(api_response.status)});
        std.debug.print("Body size: {d} bytes\n", .{api_response.body.len});
        std.debug.print("=== REQUEST COMPLETE ===\n\n", .{});

        response.status = api_response.status;
        try response.setHeader("Content-Type", "application/json");
        try response.setBody(api_response.body);
    }
};

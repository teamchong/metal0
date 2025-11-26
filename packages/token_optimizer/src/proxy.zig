const std = @import("std");
const compress = @import("compress.zig");

pub const ProxyServer = struct {
    allocator: std.mem.Allocator,
    compressor: compress.TextCompressor,

    pub fn init(allocator: std.mem.Allocator) ProxyServer {
        return ProxyServer{
            .allocator = allocator,
            .compressor = compress.TextCompressor.init(allocator),
        };
    }

    pub fn listen(self: *ProxyServer, port: u16) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", port);
        var server = try address.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        std.debug.print("Proxy listening on http://127.0.0.1:{d}\n", .{port});

        while (true) {
            const connection = try server.accept();
            try self.handleConnection(connection);
        }
    }

    fn handleConnection(self: *ProxyServer, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        var buf: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buf);
        if (bytes_read == 0) return;

        const request = buf[0..bytes_read];

        // Parse HTTP request line
        var lines = std.mem.splitScalar(u8, request, '\n');
        const request_line = lines.next() orelse return;

        // Extract method and path
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;

        std.debug.print("\n=== INCOMING REQUEST ===\n", .{});
        std.debug.print("Method: {s}\n", .{method});
        std.debug.print("Path: {s}\n", .{path});

        // Extract headers
        var headers = std.ArrayList(std.http.Header){};
        defer headers.deinit(self.allocator);

        var body_start: usize = 0;
        var current_pos: usize = request_line.len + 1;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0) {
                body_start = current_pos + trimmed.len + 1;
                break;
            }

            if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon_pos| {
                const name = std.mem.trim(u8, trimmed[0..colon_pos], &std.ascii.whitespace);
                const value = std.mem.trim(u8, trimmed[colon_pos + 1 ..], &std.ascii.whitespace);
                try headers.append(self.allocator, .{
                    .name = name,
                    .value = value,
                });
            }
            current_pos += line.len + 1;
        }

        const body = if (body_start < request.len) request[body_start..] else &[_]u8{};

        std.debug.print("Headers count: {d}\n", .{headers.items.len});
        for (headers.items) |header| {
            std.debug.print("  {s}: {s}\n", .{ header.name, header.value });
        }
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
        const uri_str = try std.fmt.allocPrint(self.allocator, "https://api.anthropic.com{s}", .{path});
        defer self.allocator.free(uri_str);

        const uri = try std.Uri.parse(uri_str);
        std.debug.print("Target: {s}\n", .{uri_str});

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        const http_method = if (std.mem.eql(u8, method, "POST"))
            std.http.Method.POST
        else if (std.mem.eql(u8, method, "GET"))
            std.http.Method.GET
        else
            std.http.Method.POST;

        std.debug.print("HTTP Method: {s}\n", .{@tagName(http_method)});
        std.debug.print("Forwarding {d} headers\n", .{headers.items.len});
        std.debug.print("Body size: {d} bytes\n", .{compressed_body.len});

        // Forward request to Anthropic API using Zig 0.15.2 API
        var req = try client.request(http_method, uri, .{
            .extra_headers = headers.items,
        });
        defer req.deinit();

        // Send request with body
        // Note: sendBodyComplete expects []u8 (mutable), but we have const - need to allocate mutable copy
        const mutable_body = try self.allocator.dupe(u8, compressed_body);
        defer self.allocator.free(mutable_body);
        try req.sendBodyComplete(mutable_body);

        // Receive response
        std.debug.print("\n=== RECEIVING RESPONSE ===\n", .{});
        var redirect_buffer: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        std.debug.print("Status: {d} {s}\n", .{ @intFromEnum(response.head.status), @tagName(response.head.status) });
        if (response.head.content_type) |ct| {
            std.debug.print("Content-Type: {s}\n", .{ct});
        }

        // Read response body
        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);

        var reader = response.reader(&.{});
        try reader.appendRemainingUnlimited(self.allocator, &response_body);

        std.debug.print("Response body size: {d} bytes\n", .{response_body.items.len});

        // Send response back to client
        std.debug.print("\n=== SENDING TO CLIENT ===\n", .{});
        std.debug.print("Status: {d} {s}\n", .{ @intFromEnum(response.head.status), @tagName(response.head.status) });
        std.debug.print("Body size: {d} bytes\n", .{response_body.items.len});
        std.debug.print("=== REQUEST COMPLETE ===\n\n", .{});
        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n",
            .{ @intFromEnum(response.head.status), @tagName(response.head.status), response_body.items.len },
        );
        defer self.allocator.free(response_header);

        try connection.stream.writeAll(response_header);
        try connection.stream.writeAll(response_body.items);
    }
};

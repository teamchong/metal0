const std = @import("std");
const compress = @import("compress.zig");
const gzip = @import("gzip");

pub const ProxyServer = struct {
    allocator: std.mem.Allocator,
    compressor: compress.TextCompressor,

    pub fn init(allocator: std.mem.Allocator, compress_enabled: bool) ProxyServer {
        return ProxyServer{
            .allocator = allocator,
            .compressor = compress.TextCompressor.init(allocator, compress_enabled),
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

        // Read full request (handle large bodies)
        var request_buffer = std.ArrayList(u8){};
        defer request_buffer.deinit(self.allocator);

        var buf: [8192]u8 = undefined;
        var content_length: ?usize = null;
        var headers_end: ?usize = null;

        // Read until we have headers
        while (headers_end == null) {
            const bytes_read = try connection.stream.read(&buf);
            if (bytes_read == 0) break;

            try request_buffer.appendSlice(self.allocator, buf[0..bytes_read]);

            // Check for end of headers
            if (std.mem.indexOf(u8, request_buffer.items, "\r\n\r\n")) |pos| {
                headers_end = pos + 4;

                // Parse Content-Length from headers
                const headers = request_buffer.items[0..pos];
                var lines = std.mem.splitScalar(u8, headers, '\n');
                while (lines.next()) |line| {
                    if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
                        const value_start = std.mem.indexOfScalar(u8, line, ':').? + 1;
                        const value = std.mem.trim(u8, line[value_start..], " \r");
                        content_length = std.fmt.parseInt(usize, value, 10) catch null;
                        break;
                    }
                }
                break;
            }
        }

        // Read remaining body if needed
        if (headers_end) |hdr_end| {
            if (content_length) |len| {
                const body_received = request_buffer.items.len - hdr_end;
                const body_remaining = if (len > body_received) len - body_received else 0;

                // Read rest of body
                var remaining = body_remaining;
                while (remaining > 0) {
                    const bytes_read = try connection.stream.read(&buf);
                    if (bytes_read == 0) break;

                    try request_buffer.appendSlice(self.allocator, buf[0..bytes_read]);
                    remaining = if (remaining > bytes_read) remaining - bytes_read else 0;
                }
            }
        }

        if (request_buffer.items.len == 0) return;
        const request = request_buffer.items;

        // Parse HTTP request line
        var lines = std.mem.splitScalar(u8, request, '\n');
        const request_line = lines.next() orelse return;

        // Extract method and path
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;

        // Handle /health endpoint
        const trimmed_path = std.mem.trim(u8, path, "\r");
        if (std.mem.eql(u8, trimmed_path, "/health")) {
            const health_response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"status\":\"ok\"}";
            try connection.stream.writeAll(health_response);
            return;
        }

        std.debug.print("\n[PROXY] {s} {s} ({d}B)\n", .{ method, trimmed_path, request_buffer.items.len });

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

        // Compress request (convert text to images)
        const compressed_body = if (body.len > 0)
            try self.compressor.compressRequest(body)
        else
            try self.allocator.dupe(u8, body);
        defer self.allocator.free(compressed_body);

        // Forward to Anthropic API
        const url_str = try std.fmt.allocPrint(self.allocator, "https://api.anthropic.com{s}", .{trimmed_path});
        defer self.allocator.free(url_str);

        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Prepare request headers
        var req_headers = std.ArrayList(std.http.Header){};
        defer req_headers.deinit(self.allocator);

        // Add anthropic-version if missing
        var has_version = false;
        for (headers.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "anthropic-version")) {
                has_version = true;
            }
        }
        if (!has_version) {
            try req_headers.append(self.allocator, .{ .name = "anthropic-version", .value = "2023-06-01" });
        }

        // Copy existing headers (skip Host and Content-Length)
        for (headers.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "host")) continue;
            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) continue;
            try req_headers.append(self.allocator, header);
        }

        const uri = try std.Uri.parse(url_str);

        var req = try client.request(.POST, uri, .{
            .extra_headers = req_headers.items,
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = compressed_body.len };
        const body_mut = @constCast(compressed_body);
        try req.sendBodyComplete(body_mut);
        try req.connection.?.flush();

        // Receive response headers
        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        // Read response body
        var transfer_buf: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buf);

        const max_size = 10 * 1024 * 1024;
        const response_bytes = try reader.*.allocRemaining(self.allocator, @enumFromInt(max_size));
        defer self.allocator.free(response_bytes);

        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);
        try response_body.appendSlice(self.allocator, response_bytes);

        const status = @intFromEnum(response.head.status);
        std.debug.print("[PROXY] Response: {d} ({d}B)\n", .{ status, response_body.items.len });

        // Log error responses
        if (status >= 400 and response_body.items.len > 0) {
            const preview_len = @min(500, response_body.items.len);
            std.debug.print("[PROXY] Error body: {s}\n", .{response_body.items[0..preview_len]});
        }

        // Extract and log token usage from response
        if (response_body.items.len > 0) {
            self.logTokenUsage(response_body.items);
        }

        // Compress response with gzip
        const compressed_response = try gzip.compress(self.allocator, response_body.items);
        defer self.allocator.free(compressed_response);

        // Preserve actual status code from API
        const status_text = switch (response.head.status) {
            .ok => "200 OK",
            .bad_request => "400 Bad Request",
            .unauthorized => "401 Unauthorized",
            .forbidden => "403 Forbidden",
            .not_found => "404 Not Found",
            .too_many_requests => "429 Too Many Requests",
            .internal_server_error => "500 Internal Server Error",
            .service_unavailable => "503 Service Unavailable",
            else => "200 OK",
        };

        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\nContent-Length: {d}\r\n\r\n",
            .{ status_text, compressed_response.len },
        );
        defer self.allocator.free(response_header);

        try connection.stream.writeAll(response_header);
        try connection.stream.writeAll(compressed_response);
    }

    /// Extract and log token usage from API response
    fn logTokenUsage(self: *ProxyServer, response_json: []const u8) void {
        _ = self;

        // Look for "usage" in response
        const usage_start = std.mem.indexOf(u8, response_json, "\"usage\"") orelse return;

        // Find the closing brace for usage object
        var brace_depth: i32 = 0;
        var usage_end: usize = usage_start;
        var in_usage = false;

        for (response_json[usage_start..], 0..) |c, i| {
            if (c == '{') {
                brace_depth += 1;
                in_usage = true;
            } else if (c == '}') {
                brace_depth -= 1;
                if (in_usage and brace_depth == 0) {
                    usage_end = usage_start + i + 1;
                    break;
                }
            }
        }

        if (usage_end <= usage_start) return;

        const usage_section = response_json[usage_start..usage_end];

        // Extract input_tokens
        var input_tokens: ?i64 = null;
        if (std.mem.indexOf(u8, usage_section, "\"input_tokens\"")) |pos| {
            const after_key = usage_section[pos + 14 ..];
            if (std.mem.indexOfScalar(u8, after_key, ':')) |colon| {
                var i = colon + 1;
                while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == '\n')) : (i += 1) {}
                var end = i;
                while (end < after_key.len and after_key[end] >= '0' and after_key[end] <= '9') : (end += 1) {}
                if (end > i) {
                    input_tokens = std.fmt.parseInt(i64, after_key[i..end], 10) catch null;
                }
            }
        }

        // Extract output_tokens
        var output_tokens: ?i64 = null;
        if (std.mem.indexOf(u8, usage_section, "\"output_tokens\"")) |pos| {
            const after_key = usage_section[pos + 15 ..];
            if (std.mem.indexOfScalar(u8, after_key, ':')) |colon| {
                var i = colon + 1;
                while (i < after_key.len and (after_key[i] == ' ' or after_key[i] == '\n')) : (i += 1) {}
                var end = i;
                while (end < after_key.len and after_key[end] >= '0' and after_key[end] <= '9') : (end += 1) {}
                if (end > i) {
                    output_tokens = std.fmt.parseInt(i64, after_key[i..end], 10) catch null;
                }
            }
        }

        if (input_tokens != null or output_tokens != null) {
            const total = (input_tokens orelse 0) + (output_tokens orelse 0);
            std.debug.print("[TOKENS] In: {?d} | Out: {?d} | Total: {d}\n", .{ input_tokens, output_tokens, total });
        }
    }
};

const std = @import("std");
const compress = @import("compress.zig");

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
            const body_len_f = @as(f64, @floatFromInt(body.len));
            const compressed_len_f = @as(f64, @floatFromInt(compressed_body.len));
            const savings = (body_len_f - compressed_len_f) / body_len_f * 100.0;
            std.debug.print(" ({d:.1}% savings)", .{savings});
        }
        std.debug.print("\n", .{});

        // Forward to Anthropic API using curl subprocess (Zig HTTP client has Cloudflare compatibility issues)
        std.debug.print("\n=== FORWARDING TO ANTHROPIC (via curl) ===\n", .{});

        // Build curl command
        var curl_args = std.ArrayList([]const u8){};
        defer curl_args.deinit(self.allocator);

        var header_strings = std.ArrayList([]const u8){};
        defer {
            for (header_strings.items) |s| self.allocator.free(s);
            header_strings.deinit(self.allocator);
        }

        try curl_args.append(self.allocator, "curl");
        try curl_args.append(self.allocator, "-s"); // Silent
        try curl_args.append(self.allocator, "-X");
        try curl_args.append(self.allocator, method);

        // Add URL
        const url = try std.fmt.allocPrint(self.allocator, "https://api.anthropic.com{s}", .{path});
        try header_strings.append(self.allocator, url);
        try curl_args.append(self.allocator, url);

        // Add headers
        for (headers.items) |header| {
            // Skip Host header (curl sets it automatically)
            if (std.ascii.eqlIgnoreCase(header.name, "host")) continue;
            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) continue; // curl sets this

            const header_str = try std.fmt.allocPrint(self.allocator, "{s}: {s}", .{ header.name, header.value });
            try header_strings.append(self.allocator, header_str);

            try curl_args.append(self.allocator, "-H");
            try curl_args.append(self.allocator, header_str);
        }

        // Add anthropic-version if missing
        var has_version = false;
        for (headers.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "anthropic-version")) {
                has_version = true;
                break;
            }
        }
        if (!has_version) {
            try curl_args.append(self.allocator, "-H");
            try curl_args.append(self.allocator, "anthropic-version: 2023-06-01");
        }

        // Add body
        try curl_args.append(self.allocator, "-d");
        try curl_args.append(self.allocator, compressed_body);

        std.debug.print("Executing curl command:\n", .{});
        for (curl_args.items, 0..) |arg, i| {
            std.debug.print("  [{d}]: {s}\n", .{ i, arg });
        }

        // Execute curl
        var child = std.process.Child.init(curl_args.items, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // Max 10MB
        defer self.allocator.free(stdout);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024); // Max 1MB
        defer self.allocator.free(stderr);

        const term = try child.wait();

        std.debug.print("\n=== CURL RESPONSE ===\n", .{});
        std.debug.print("Exit code: {any}\n", .{term});
        if (stderr.len > 0) {
            std.debug.print("Stderr: {s}\n", .{stderr});
        }

        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);
        try response_body.appendSlice(self.allocator, stdout);

        const response_content_length: ?usize = stdout.len;

        std.debug.print("Response body size: {d} bytes", .{response_body.items.len});
        if (response_content_length) |expected| {
            if (response_body.items.len != expected) {
                std.debug.print(" (WARNING: expected {d} bytes, got {d})\n", .{ expected, response_body.items.len });
            } else {
                std.debug.print(" (matches Content-Length)\n", .{});
            }
        } else {
            std.debug.print("\n", .{});
        }

        // Debug: Show first and last 100 bytes of response
        if (response_body.items.len > 0) {
            const preview_size = @min(100, response_body.items.len);
            std.debug.print("Response preview (first {d} bytes): {s}\n", .{ preview_size, response_body.items[0..preview_size] });

            if (response_body.items.len > 100) {
                const tail_start = response_body.items.len - 100;
                std.debug.print("Response tail (last 100 bytes): {s}\n", .{response_body.items[tail_start..]});
            }
        }

        // Send response back to client (no compression - Zig 0.15.2 lacks gzip)
        std.debug.print("\n=== SENDING TO CLIENT ===\n", .{});
        std.debug.print("Status: 200 OK\n", .{});
        std.debug.print("Body size: {d} bytes\n", .{response_body.items.len});
        std.debug.print("=== REQUEST COMPLETE ===\n\n", .{});

        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n",
            .{response_body.items.len},
        );
        defer self.allocator.free(response_header);

        try connection.stream.writeAll(response_header);
        try connection.stream.writeAll(response_body.items);
    }
};

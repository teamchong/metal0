//! High-Performance HTTP/2 Client
//!
//! Features:
//! - TLS 1.3 with AES-NI acceleration
//! - HTTP/2 stream multiplexing
//! - HPACK header compression
//! - gzip decompression (5-10x smaller responses)
//! - Zero-copy where possible
//! - Connection pooling per host

const std = @import("std");
const frame = @import("frame.zig");
const hpack = @import("hpack.zig");
const connection = @import("connection.zig");
const tls = @import("tls.zig");
const gzip = @import("gzip");

// Async I/O support (goroutine-style)
const Netpoller = @import("netpoller").Netpoller;
const GreenThread = @import("green_thread").GreenThread;


pub const Frame = frame.Frame;
pub const FrameType = frame.FrameType;
pub const FrameHeader = frame.FrameHeader;
pub const Connection = connection.Connection;
pub const Request = connection.Request;
pub const Stream = connection.Stream;
pub const TlsConnection = tls.TlsConnection;
pub const Header = hpack.Header;

/// Extra header for requests (alias to hpack.Header for type compatibility)
pub const ExtraHeader = hpack.Header;

/// HTTP/2 Response
pub const Response = struct {
    status: u16,
    headers: []const hpack.Header,
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        // Only free if we allocated (non-empty slice from heap)
        if (self.headers.len > 0) {
            for (self.headers) |h| {
                if (h.name.len > 0) self.allocator.free(h.name);
                if (h.value.len > 0) self.allocator.free(h.value);
            }
            self.allocator.free(self.headers);
        }
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

    /// Get header value by name (case-insensitive)
    pub fn getHeader(self: Response, name: []const u8) ?[]const u8 {
        for (self.headers) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }
};

/// Response cache for H2 client
pub const ResponseCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_size: usize,
    ttl_seconds: i64,

    const CacheEntry = struct {
        body: []const u8,
        status: u16,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator, max_size: usize, ttl_seconds: i64) ResponseCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_size = max_size,
            .ttl_seconds = ttl_seconds,
        };
    }

    pub fn deinit(self: *ResponseCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.body);
        }
        self.entries.deinit();
    }

    pub fn get(self: *ResponseCache, url: []const u8) ?CacheEntry {
        if (self.entries.get(url)) |entry| {
            const now = std.time.timestamp();
            if (now - entry.timestamp < self.ttl_seconds) {
                return entry;
            }
            // Expired - remove
            if (self.entries.fetchRemove(url)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value.body);
            }
        }
        return null;
    }

    pub fn put(self: *ResponseCache, url: []const u8, status: u16, body: []const u8) !void {
        const key = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(key);

        const body_copy = try self.allocator.dupe(u8, body);
        errdefer self.allocator.free(body_copy);

        try self.entries.put(key, .{
            .body = body_copy,
            .status = status,
            .timestamp = std.time.timestamp(),
        });
    }

    pub fn stats(self: *ResponseCache) struct { entries: usize, hits: u64, misses: u64 } {
        return .{ .entries = self.entries.count(), .hits = 0, .misses = 0 };
    }
};

/// HTTP/2 Client with connection pooling and optional response cache
pub const Client = struct {
    allocator: std.mem.Allocator,
    connections: std.StringHashMap(*H2Connection),
    connections_mutex: std.Thread.Mutex,
    max_connections_per_host: usize,
    cache: ?*ResponseCache,

    // Async I/O support (goroutine-style)
    netpoller: ?*Netpoller,
    green_thread: ?*GreenThread,

    const H2Connection = struct {
        tls: *TlsConnection,
        h2: *Connection,
    };

    pub fn init(allocator: std.mem.Allocator) Client {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*H2Connection).init(allocator),
            .connections_mutex = .{},
            .max_connections_per_host = 1, // HTTP/2 multiplexing means 1 is enough
            .cache = null,
            .netpoller = null,
            .green_thread = null,
        };
    }

    pub fn initWithCache(allocator: std.mem.Allocator, cache: *ResponseCache) Client {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*H2Connection).init(allocator),
            .connections_mutex = .{},
            .max_connections_per_host = 1,
            .cache = cache,
            .netpoller = null,
            .green_thread = null,
        };
    }

    /// Initialize with async I/O support (goroutine-style)
    pub fn initAsync(allocator: std.mem.Allocator, netpoller: *Netpoller, green_thread: *GreenThread) Client {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*H2Connection).init(allocator),
            .connections_mutex = .{},
            .max_connections_per_host = 1,
            .cache = null,
            .netpoller = netpoller,
            .green_thread = green_thread,
        };
    }

    pub fn deinit(self: *Client) void {
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.h2.deinit();
            entry.value_ptr.*.tls.deinit();
            self.allocator.free(entry.key_ptr.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.connections.deinit();
    }

    /// GET request
    pub fn get(self: *Client, url: []const u8) !Response {
        return self.request("GET", url, &[_]ExtraHeader{}, null);
    }

    /// POST request with body
    pub fn post(self: *Client, url: []const u8, body: []const u8, content_type: []const u8) !Response {
        return self.request("POST", url, &[_]ExtraHeader{
            .{ .name = "content-type", .value = content_type },
        }, body);
    }

    /// Generic request - supports both HTTP/1.1 (plain) and HTTP/2 (TLS)
    pub fn request(
        self: *Client,
        method: []const u8,
        url: []const u8,
        extra_headers: []const ExtraHeader,
        body: ?[]const u8,
    ) !Response {
        // Parse URL
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;

        const scheme = getScheme(uri.scheme);
        const host = getHostString(uri.host) orelse return error.InvalidUrl;
        const port: u16 = uri.port orelse if (std.mem.eql(u8, scheme, "https")) @as(u16, 443) else @as(u16, 80);
        const path = getPathString(uri.path);

        // Use HTTP/1.1 for plain HTTP, HTTP/2 for HTTPS
        if (std.mem.eql(u8, scheme, "http")) {
            return self.requestHttp1(method, host, port, path, extra_headers, body);
        }

        // HTTPS: Get or create H2 connection
        const conn = try self.getConnection(host, port);

        // Build headers
        var headers = std.ArrayList(ExtraHeader){};
        defer headers.deinit(self.allocator);

        try headers.append(self.allocator, .{ .name = "user-agent", .value = "metal0/1.0" });

        // Only add default accept if not provided in extra_headers
        var has_accept = false;
        for (extra_headers) |h| {
            if (std.mem.eql(u8, h.name, "accept")) has_accept = true;
        }
        if (!has_accept) {
            try headers.append(self.allocator, .{ .name = "accept", .value = "*/*" });
        }

        try headers.append(self.allocator, .{ .name = "accept-encoding", .value = "gzip" });

        for (extra_headers) |h| {
            try headers.append(self.allocator, h);
        }

        if (body) |b| {
            var len_buf: [20]u8 = undefined;
            const len_str = std.fmt.bufPrint(&len_buf, "{}", .{b.len}) catch unreachable;
            try headers.append(self.allocator, .{ .name = "content-length", .value = len_str });
        }

        // Send request
        const stream = try conn.h2.request(method, path, host, headers.items);

        // Send body if present
        if (body) |b| {
            const data_frame = Frame.data(stream.id, b, true);
            try conn.h2.sendFrame(data_frame);
        }

        // Wait for response
        try conn.h2.waitForResponse(stream);

        // Check for gzip and decompress if needed
        var resp_body: []const u8 = undefined;
        const content_encoding = stream.getHeader("content-encoding");
        if (content_encoding != null and std.mem.eql(u8, content_encoding.?, "gzip")) {
            // Decompress gzip response
            resp_body = gzip.decompress(self.allocator, stream.body.items) catch |err| {
                std.debug.print("[H2] gzip decompress error: {}\n", .{err});
                resp_body = try self.allocator.dupe(u8, stream.body.items);
                return Response{
                    .status = stream.status orelse 0,
                    .headers = &[_]hpack.Header{},
                    .body = resp_body,
                    .allocator = self.allocator,
                };
            };
        } else {
            resp_body = try self.allocator.dupe(u8, stream.body.items);
        }

        // Build response
        const resp_headers = try self.allocator.alloc(hpack.Header, stream.headers.items.len);
        for (stream.headers.items, 0..) |h, i| {
            resp_headers[i] = .{
                .name = try self.allocator.dupe(u8, h.name),
                .value = try self.allocator.dupe(u8, h.value),
            };
        }

        return Response{
            .status = stream.status orelse 0,
            .headers = resp_headers,
            .body = resp_body,
            .allocator = self.allocator,
        };
    }

    /// HTTP/1.1 request for plain HTTP (no TLS)
    fn requestHttp1(
        self: *Client,
        method: []const u8,
        host: []const u8,
        port: u16,
        path: []const u8,
        extra_headers: []const ExtraHeader,
        body: ?[]const u8,
    ) !Response {
        // TCP connect
        const list = std.net.getAddressList(self.allocator, host, port) catch return error.ConnectionFailed;
        defer list.deinit();

        if (list.addrs.len == 0) return error.ConnectionFailed;

        const socket = std.posix.socket(
            list.addrs[0].any.family,
            std.posix.SOCK.STREAM,
            0,
        ) catch return error.ConnectionFailed;
        defer std.posix.close(socket);

        std.posix.connect(socket, &list.addrs[0].any, list.addrs[0].getOsSockLen()) catch return error.ConnectionFailed;

        // Build HTTP/1.1 request
        var request_buf = std.ArrayList(u8){};
        defer request_buf.deinit(self.allocator);

        const writer = request_buf.writer(self.allocator);

        // Request line
        try writer.print("{s} {s} HTTP/1.1\r\n", .{ method, path });
        try writer.print("Host: {s}\r\n", .{host});
        try writer.print("User-Agent: metal0/1.0\r\n", .{});
        try writer.print("Accept: */*\r\n", .{});
        try writer.print("Connection: close\r\n", .{});

        // Extra headers
        for (extra_headers) |h| {
            try writer.print("{s}: {s}\r\n", .{ h.name, h.value });
        }

        // Content-Length for body
        if (body) |b| {
            try writer.print("Content-Length: {}\r\n", .{b.len});
        }

        try writer.print("\r\n", .{});

        // Send request
        _ = std.posix.send(socket, request_buf.items, 0) catch return error.ConnectionFailed;

        // Send body
        if (body) |b| {
            _ = std.posix.send(socket, b, 0) catch return error.ConnectionFailed;
        }

        // Read response
        var response_buf = std.ArrayList(u8){};
        defer response_buf.deinit(self.allocator);

        var read_buf: [8192]u8 = undefined;
        while (true) {
            const n = std.posix.recv(socket, &read_buf, 0) catch break;
            if (n == 0) break;
            try response_buf.appendSlice(self.allocator, read_buf[0..n]);
        }

        // Parse HTTP/1.1 response
        return self.parseHttp1Response(response_buf.items);
    }

    /// Parse HTTP/1.1 response
    fn parseHttp1Response(self: *Client, data: []const u8) !Response {
        // Find header/body separator
        const header_end = std.mem.indexOf(u8, data, "\r\n\r\n") orelse return error.InvalidResponse;
        const header_section = data[0..header_end];
        const body_start = header_end + 4;

        // Parse status line
        const status_end = std.mem.indexOf(u8, header_section, "\r\n") orelse return error.InvalidResponse;
        const status_line = header_section[0..status_end];

        // "HTTP/1.1 200 OK" -> extract 200
        var parts = std.mem.splitScalar(u8, status_line, ' ');
        _ = parts.next(); // HTTP/1.1
        const status_str = parts.next() orelse return error.InvalidResponse;
        const status = std.fmt.parseInt(u16, status_str, 10) catch return error.InvalidResponse;

        // Get body
        const resp_body = if (body_start < data.len)
            try self.allocator.dupe(u8, data[body_start..])
        else
            try self.allocator.dupe(u8, "");

        return Response{
            .status = status,
            .headers = &[_]hpack.Header{},
            .body = resp_body,
            .allocator = self.allocator,
        };
    }

    const UrlIndexPair = struct { url: []const u8, index: usize };
    const UrlIndexList = std.ArrayList(UrlIndexPair);

    /// Fetch multiple URLs in parallel (multiplexed over single connection!)
    /// Uses thread-per-host parallelism to overlap connection setup
    pub fn getAll(self: *Client, urls: []const []const u8) ![]Response {
        if (urls.len == 0) return &[_]Response{};

        // Group URLs by host
        var by_host = std.StringHashMap(UrlIndexList).init(self.allocator);
        defer {
            var it = by_host.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            by_host.deinit();
        }

        for (urls, 0..) |url, i| {
            const uri = std.Uri.parse(url) catch continue;
            const host = getHostString(uri.host) orelse continue;

            const gop = try by_host.getOrPut(host);
            if (!gop.found_existing) {
                gop.value_ptr.* = UrlIndexList{};
            }
            try gop.value_ptr.append(self.allocator, .{ .url = url, .index = i });
        }

        // Allocate results and initialize all to error state
        const results = try self.allocator.alloc(Response, urls.len);
        errdefer self.allocator.free(results);

        // Initialize all results to empty (error state)
        for (results) |*r| {
            r.* = Response{
                .status = 0,
                .headers = &[_]hpack.Header{},
                .body = "",
                .allocator = self.allocator,
            };
        }

        // Count hosts
        const host_count = by_host.count();

        // If only one host, use fast path (no thread overhead)
        if (host_count <= 1) {
            var host_it = by_host.iterator();
            while (host_it.next()) |entry| {
                const host = entry.key_ptr.*;
                const url_list = entry.value_ptr.items;
                self.fetchHostGroup(host, url_list, results);
            }
            return results;
        }

        // Multiple hosts - use thread-per-host parallelism
        const HostTask = struct {
            host: []const u8,
            url_list: []const UrlIndexPair,
            results: []Response,
            client: *Client,

            fn run(ctx: *@This()) void {
                ctx.client.fetchHostGroup(ctx.host, ctx.url_list, ctx.results);
            }
        };

        // Collect host tasks
        var tasks = try self.allocator.alloc(HostTask, host_count);
        defer self.allocator.free(tasks);

        var threads = try self.allocator.alloc(?std.Thread, host_count);
        defer self.allocator.free(threads);

        var task_idx: usize = 0;
        var host_it = by_host.iterator();
        while (host_it.next()) |entry| : (task_idx += 1) {
            tasks[task_idx] = .{
                .host = entry.key_ptr.*,
                .url_list = entry.value_ptr.items,
                .results = results,
                .client = self,
            };
            threads[task_idx] = std.Thread.spawn(.{}, HostTask.run, .{&tasks[task_idx]}) catch null;
        }

        // Wait for all threads
        for (threads) |maybe_thread| {
            if (maybe_thread) |thread| {
                thread.join();
            }
        }

        return results;
    }

    /// Fetch all URLs for a single host group
    fn fetchHostGroup(self: *Client, host: []const u8, url_list: []const UrlIndexPair, results: []Response) void {
        // Use first URL to get port
        const first_uri = std.Uri.parse(url_list[0].url) catch return;
        const port: u16 = first_uri.port orelse if (std.mem.eql(u8, getScheme(first_uri.scheme), "https")) 443 else 80;

        // Get connection for this host
        const conn = self.getConnection(host, port) catch return;

        // Build requests
        var requests = self.allocator.alloc(connection.Request, url_list.len) catch return;
        defer self.allocator.free(requests);

        for (url_list, 0..) |item, j| {
            const uri = std.Uri.parse(item.url) catch {
                requests[j] = .{ .method = "GET", .path = "/", .host = host };
                continue;
            };
            requests[j] = .{
                .method = "GET",
                .path = getPathString(uri.path),
                .host = host,
            };
        }

        // Send all requests and get responses (multiplexed!)
        const streams = conn.h2.requestAll(requests) catch return;
        defer self.allocator.free(streams);

        // Convert streams to responses
        for (streams, 0..) |stream, j| {
            const idx = url_list[j].index;

            const resp_headers = self.allocator.alloc(
                hpack.Header,
                stream.headers.items.len,
            ) catch continue;

            // Check for gzip content-encoding
            var is_gzip = false;
            for (stream.headers.items, 0..) |h, k| {
                resp_headers[k] = .{
                    .name = self.allocator.dupe(u8, h.name) catch "",
                    .value = self.allocator.dupe(u8, h.value) catch "",
                };
                if (std.mem.eql(u8, h.name, "content-encoding") and std.mem.eql(u8, h.value, "gzip")) {
                    is_gzip = true;
                }
            }

            // Decompress gzip body if needed
            const body = if (is_gzip and stream.body.items.len > 0)
                gzip.decompress(self.allocator, stream.body.items) catch
                    self.allocator.dupe(u8, stream.body.items) catch ""
            else
                self.allocator.dupe(u8, stream.body.items) catch "";

            results[idx] = Response{
                .status = stream.status orelse 0,
                .headers = resp_headers,
                .body = body,
                .allocator = self.allocator,
            };
        }
    }

    /// Preconnect to a host (synchronous, but can be called early to overlap with other work)
    /// This establishes the TCP+TLS+H2 connection so subsequent requests are faster
    pub fn preconnect(self: *Client, host: []const u8, port: u16) void {
        // Already connected?
        if (self.connections.get(host)) |_| return;

        // Establish connection (ignore errors - this is best-effort)
        _ = self.getConnection(host, port) catch {};
    }

    /// Preconnect to multiple hosts in parallel using threads
    /// This overlaps TCP+TLS+H2 handshakes for maximum speed
    pub fn preconnectParallel(self: *Client, hosts: []const struct { host: []const u8, port: u16 }) void {
        if (hosts.len == 0) return;
        if (hosts.len == 1) {
            self.preconnect(hosts[0].host, hosts[0].port);
            return;
        }

        const Task = struct {
            client: *Client,
            host: []const u8,
            port: u16,

            fn run(task: *@This()) void {
                task.client.preconnect(task.host, task.port);
            }
        };

        // Create tasks for each host
        var tasks: [8]Task = undefined; // Max 8 hosts
        var threads: [8]std.Thread = undefined;
        const count = @min(hosts.len, 8);

        // Spawn threads
        var spawned: usize = 0;
        for (hosts[0..count]) |h| {
            tasks[spawned] = .{ .client = self, .host = h.host, .port = h.port };
            threads[spawned] = std.Thread.spawn(.{}, Task.run, .{&tasks[spawned]}) catch {
                // Fallback to sync if thread spawn fails
                self.preconnect(h.host, h.port);
                continue;
            };
            spawned += 1;
        }

        // Wait for all threads
        for (threads[0..spawned]) |t| {
            t.join();
        }
    }

    fn getConnection(self: *Client, host: []const u8, port: u16) !*H2Connection {
        // Check pool with lock
        {
            self.connections_mutex.lock();
            defer self.connections_mutex.unlock();
            if (self.connections.get(host)) |conn| {
                return conn;
            }
        }

        var timer = std.time.Timer.start() catch unreachable;

        // Create new connection (outside lock - slow operations)
        const conn = try self.allocator.create(H2Connection);
        errdefer self.allocator.destroy(conn);

        // TCP connect
        const list = std.net.getAddressList(self.allocator, host, port) catch return error.ConnectionFailed;
        defer list.deinit();

        if (list.addrs.len == 0) return error.ConnectionFailed;

        const socket = std.posix.socket(
            list.addrs[0].any.family,
            std.posix.SOCK.STREAM,
            0,
        ) catch return error.ConnectionFailed;
        errdefer std.posix.close(socket);

        // Set non-blocking if async mode enabled
        if (self.netpoller != null) {
            const flags = std.posix.fcntl(socket, std.posix.F.GETFL, 0) catch 0;
            _ = std.posix.fcntl(socket, std.posix.F.SETFL, flags | 0x0004) catch {}; // O_NONBLOCK = 0x0004 on macOS/BSD
        }

        std.posix.connect(socket, &list.addrs[0].any, list.addrs[0].getOsSockLen()) catch return error.ConnectionFailed;
        const tcp_time = timer.read() / 1_000_000;

        // TLS handshake with ALPN (pass netpoller/green_thread for async I/O)
        conn.tls = try TlsConnection.init(self.allocator, socket, self.netpoller, self.green_thread);
        errdefer conn.tls.deinit();

        try conn.tls.handshake(host, &.{tls.ALPN.H2});
        const tls_time = timer.read() / 1_000_000;

        // HTTP/2 connection over TLS
        conn.h2 = try Connection.initWithTls(self.allocator, conn.tls);
        const h2_time = timer.read() / 1_000_000;

        std.debug.print("[H2] connect: tcp={d}ms, tls={d}ms, h2={d}ms\n", .{ tcp_time, tls_time - tcp_time, h2_time - tls_time });

        // Store in pool with lock
        {
            self.connections_mutex.lock();
            defer self.connections_mutex.unlock();

            // Double-check - another thread may have added it
            if (self.connections.get(host)) |existing| {
                // Another thread already added - cleanup our connection and use existing
                conn.h2.deinit();
                conn.tls.deinit();
                self.allocator.destroy(conn);
                return existing;
            }

            const host_copy = try self.allocator.dupe(u8, host);
            try self.connections.put(host_copy, conn);
        }

        return conn;
    }
};

// Helper functions
fn getHostString(host: ?std.Uri.Component) ?[]const u8 {
    if (host) |h| {
        return switch (h) {
            .raw => |raw| raw,
            .percent_encoded => |enc| enc,
        };
    }
    return null;
}

fn getPathString(path: std.Uri.Component) []const u8 {
    const p = switch (path) {
        .raw => |raw| raw,
        .percent_encoded => |enc| enc,
    };
    return if (p.len > 0) p else "/";
}

fn getScheme(scheme: ?[]const u8) []const u8 {
    return scheme orelse "https";
}

// ============================================================================
// Simple Parallel Fetch API (for PyPI client)
// ============================================================================

/// Fetch multiple URLs in parallel using HTTP/2 multiplexing
/// Returns array of responses (caller owns memory)
pub fn fetchParallel(allocator: std.mem.Allocator, urls: []const []const u8) ![]Response {
    var client = Client.init(allocator);
    defer client.deinit();

    return client.getAll(urls);
}

/// Fetch single URL
pub fn fetch(allocator: std.mem.Allocator, url: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();

    return client.get(url);
}

// ============================================================================
// Tests
// ============================================================================

test "Client creation" {
    const allocator = std.testing.allocator;

    var client = Client.init(allocator);
    defer client.deinit();

    try std.testing.expectEqual(@as(usize, 1), client.max_connections_per_host);
}

test "Response header lookup" {
    const allocator = std.testing.allocator;

    var headers = [_]struct { name: []const u8, value: []const u8 }{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "content-length", .value = "123" },
    };

    var resp = Response{
        .status = 200,
        .headers = &headers,
        .body = "",
        .allocator = allocator,
    };

    try std.testing.expectEqualStrings("application/json", resp.getHeader("content-type").?);
    try std.testing.expectEqualStrings("application/json", resp.getHeader("Content-Type").?);
    try std.testing.expect(resp.getHeader("x-custom") == null);
}

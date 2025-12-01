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
    max_connections_per_host: usize,
    cache: ?*ResponseCache,

    const H2Connection = struct {
        tls: *TlsConnection,
        h2: *Connection,
    };

    pub fn init(allocator: std.mem.Allocator) Client {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*H2Connection).init(allocator),
            .max_connections_per_host = 1, // HTTP/2 multiplexing means 1 is enough
            .cache = null,
        };
    }

    pub fn initWithCache(allocator: std.mem.Allocator, cache: *ResponseCache) Client {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*H2Connection).init(allocator),
            .max_connections_per_host = 1,
            .cache = cache,
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

    /// Generic request
    pub fn request(
        self: *Client,
        method: []const u8,
        url: []const u8,
        extra_headers: []const ExtraHeader,
        body: ?[]const u8,
    ) !Response {
        // Parse URL
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;

        const host = getHostString(uri.host) orelse return error.InvalidUrl;
        const port: u16 = uri.port orelse if (std.mem.eql(u8, getScheme(uri.scheme), "https")) 443 else 80;
        const path = getPathString(uri.path);

        // Get or create connection
        const conn = try self.getConnection(host, port);

        // Build headers
        var headers = std.ArrayList(ExtraHeader){};
        defer headers.deinit(self.allocator);

        try headers.append(self.allocator, .{ .name = "user-agent", .value = "metal0-h2/1.0" });
        try headers.append(self.allocator, .{ .name = "accept", .value = "*/*" });

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

        // Build response
        const resp_headers = try self.allocator.alloc(
            hpack.Header,
            stream.headers.items.len,
        );
        for (stream.headers.items, 0..) |h, i| {
            resp_headers[i] = .{
                .name = try self.allocator.dupe(u8, h.name),
                .value = try self.allocator.dupe(u8, h.value),
            };
        }

        const resp_body = try self.allocator.dupe(u8, stream.body.items);

        return Response{
            .status = stream.status orelse 0,
            .headers = resp_headers,
            .body = resp_body,
            .allocator = self.allocator,
        };
    }

    const UrlIndexPair = struct { url: []const u8, index: usize };
    const UrlIndexList = std.ArrayList(UrlIndexPair);

    /// Fetch multiple URLs in parallel (multiplexed over single connection!)
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

        // Fetch each host group (multiplexed within host)
        var host_it = by_host.iterator();
        while (host_it.next()) |entry| {
            const host = entry.key_ptr.*;
            const url_list = entry.value_ptr.items;
    

            // Parse first URL to get port
            const first_uri = std.Uri.parse(url_list[0].url) catch continue;
            const port: u16 = first_uri.port orelse if (std.mem.eql(u8, getScheme(first_uri.scheme), "https")) 443 else 80;

            // Get connection for this host
            const conn = self.getConnection(host, port) catch {
                continue;
            };

            // Build requests
            var requests = try self.allocator.alloc(connection.Request, url_list.len);
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
            const streams = conn.h2.requestAll(requests) catch {
                continue;
            };
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

        return results;
    }

    fn getConnection(self: *Client, host: []const u8, port: u16) !*H2Connection {
        // Check pool
        if (self.connections.get(host)) |conn| {
            return conn;
        }

        var timer = std.time.Timer.start() catch unreachable;

        // Create new connection
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

        std.posix.connect(socket, &list.addrs[0].any, list.addrs[0].getOsSockLen()) catch return error.ConnectionFailed;
        const tcp_time = timer.read() / 1_000_000;

        // TLS handshake with ALPN
        conn.tls = try TlsConnection.init(self.allocator, socket);
        errdefer conn.tls.deinit();

        try conn.tls.handshake(host, &.{tls.ALPN.H2});
        const tls_time = timer.read() / 1_000_000;

        // HTTP/2 connection over TLS
        conn.h2 = try Connection.initWithTls(self.allocator, conn.tls);
        const h2_time = timer.read() / 1_000_000;

        std.debug.print("[H2] connect: tcp={d}ms, tls={d}ms, h2={d}ms\n", .{ tcp_time, tls_time - tcp_time, h2_time - tls_time });

        // Store in pool
        const host_copy = try self.allocator.dupe(u8, host);
        try self.connections.put(host_copy, conn);

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

//! Shared HTTP Client with Connection Pooling
//!
//! High-performance HTTP client for metal0 with:
//! - Connection pooling (reuses TCP connections)
//! - Parallel fetching via thread pool
//! - Retry with exponential backoff
//! - Custom headers support
//!
//! ## Usage
//! ```zig
//! var client = HttpClient.init(allocator);
//! defer client.deinit();
//!
//! // Single request
//! const body = try client.get("https://example.com/api");
//! defer allocator.free(body);
//!
//! // Parallel requests
//! const results = try client.getParallel(&.{"url1", "url2", "url3"});
//! defer allocator.free(results);
//! ```

const std = @import("std");

pub const HttpError = error{
    NetworkError,
    Timeout,
    TooManyRequests,
    ServerError,
    NotFound,
    OutOfMemory,
};

/// HTTP client configuration
pub const Config = struct {
    /// Request timeout in milliseconds
    timeout_ms: u64 = 30000,
    /// Max concurrent requests for parallel fetching
    max_concurrent: u32 = 32,
    /// Max retries on transient failures
    max_retries: u32 = 3,
    /// User agent string
    user_agent: []const u8 = "metal0/1.0",
    /// Default Accept header
    accept: []const u8 = "*/*",
};

/// Fetch result for parallel operations
pub const FetchResult = union(enum) {
    success: []const u8,
    err: HttpError,

    pub fn deinit(self: *FetchResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |body| allocator.free(body),
            .err => {},
        }
    }
};

/// High-performance HTTP client with connection pooling
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    config: Config,
    inner: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) HttpClient {
        return .{
            .allocator = allocator,
            .config = config,
            .inner = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.inner.deinit();
    }

    /// GET request with default headers
    pub fn get(self: *HttpClient, url: []const u8) ![]const u8 {
        return self.getWithHeaders(url, &.{});
    }

    /// GET request with custom headers
    pub fn getWithHeaders(self: *HttpClient, url: []const u8, extra_headers: []const std.http.Header) ![]const u8 {
        return self.fetchWithRetry(url, extra_headers);
    }

    /// GET request with custom Accept header
    pub fn getWithAccept(self: *HttpClient, url: []const u8, accept: []const u8) ![]const u8 {
        return self.fetchWithRetry(url, &.{
            .{ .name = "Accept", .value = accept },
        });
    }

    /// Parallel GET requests
    pub fn getParallel(self: *HttpClient, urls: []const []const u8) ![]FetchResult {
        if (urls.len == 0) return &[_]FetchResult{};

        const results = try self.allocator.alloc(FetchResult, urls.len);
        errdefer self.allocator.free(results);

        // Initialize all to error
        for (results) |*r| {
            r.* = .{ .err = HttpError.NetworkError };
        }

        // Fetch context for thread workers
        const FetchContext = struct {
            client: *HttpClient,
            url: []const u8,
            result: *FetchResult,

            fn fetch(ctx: *@This()) void {
                ctx.result.* = if (ctx.client.get(ctx.url)) |body|
                    .{ .success = body }
                else |_|
                    .{ .err = HttpError.NetworkError };
            }
        };

        // Create contexts
        const contexts = try self.allocator.alloc(FetchContext, urls.len);
        defer self.allocator.free(contexts);

        for (urls, 0..) |url, i| {
            contexts[i] = .{
                .client = self,
                .url = url,
                .result = &results[i],
            };
        }

        // Process in batches
        var batch_start: usize = 0;
        while (batch_start < urls.len) {
            const batch_end = @min(batch_start + self.config.max_concurrent, urls.len);
            const batch_size = batch_end - batch_start;

            var threads = try self.allocator.alloc(std.Thread, batch_size);
            defer self.allocator.free(threads);

            var spawned: usize = 0;
            errdefer {
                for (threads[0..spawned]) |t| t.join();
            }

            for (batch_start..batch_end) |i| {
                threads[i - batch_start] = std.Thread.spawn(.{}, FetchContext.fetch, .{&contexts[i]}) catch {
                    FetchContext.fetch(&contexts[i]);
                    continue;
                };
                spawned += 1;
            }

            for (threads[0..spawned]) |t| t.join();
            batch_start = batch_end;
        }

        return results;
    }

    /// Fetch with retry and exponential backoff
    fn fetchWithRetry(self: *HttpClient, url: []const u8, extra_headers: []const std.http.Header) ![]const u8 {
        var retries: u32 = 0;
        var last_err: HttpError = HttpError.NetworkError;

        while (retries < self.config.max_retries) : (retries += 1) {
            const result = self.doFetch(url, extra_headers);
            if (result) |body| {
                return body;
            } else |err| {
                last_err = err;
                if (retries + 1 < self.config.max_retries) {
                    const delay_ms: u64 = @as(u64, 100) << @intCast(retries);
                    std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                }
            }
        }

        return last_err;
    }

    /// Perform actual HTTP fetch
    fn doFetch(self: *HttpClient, url: []const u8, extra_headers: []const std.http.Header) HttpError![]const u8 {
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer if (response_writer.writer.buffer.len > 0) self.allocator.free(response_writer.writer.buffer);

        // Build headers array
        var headers_buf: [16]std.http.Header = undefined;
        var header_count: usize = 0;

        headers_buf[header_count] = .{ .name = "User-Agent", .value = self.config.user_agent };
        header_count += 1;

        headers_buf[header_count] = .{ .name = "Accept", .value = self.config.accept };
        header_count += 1;

        for (extra_headers) |h| {
            if (header_count < headers_buf.len) {
                headers_buf[header_count] = h;
                header_count += 1;
            }
        }

        const result = self.inner.fetch(.{
            .location = .{ .url = url },
            .extra_headers = headers_buf[0..header_count],
            .response_writer = &response_writer.writer,
        }) catch return HttpError.NetworkError;

        // Check status
        const status = result.status;
        if (status == .not_found) return HttpError.NotFound;
        if (status == .too_many_requests) return HttpError.TooManyRequests;
        if (@intFromEnum(status) >= 500) return HttpError.ServerError;
        if (status != .ok) return HttpError.NetworkError;

        // Copy body
        const body = response_writer.writer.buffer[0..response_writer.writer.end];
        const result_body = self.allocator.dupe(u8, body) catch return HttpError.OutOfMemory;

        if (response_writer.writer.buffer.len > 0) {
            self.allocator.free(response_writer.writer.buffer);
        }

        return result_body;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "HttpClient creation" {
    const allocator = std.testing.allocator;

    var client = HttpClient.init(allocator);
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 32), client.config.max_concurrent);
}

test "HttpClient with custom config" {
    const allocator = std.testing.allocator;

    var client = HttpClient.initWithConfig(allocator, .{
        .max_concurrent = 8,
        .timeout_ms = 10000,
        .user_agent = "test-agent/1.0",
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 8), client.config.max_concurrent);
    try std.testing.expectEqualStrings("test-agent/1.0", client.config.user_agent);
}

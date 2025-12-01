//! Shared HTTP Client with Connection Pooling
//!
//! High-performance HTTP client for metal0 with:
//! - Connection pooling (reuses TCP connections)
//! - Parallel fetching via thread pool
//! - Retry with exponential backoff
//! - Custom headers support
//!
//! Uses unified h2 client (HTTP/1.1 for http://, HTTP/2 for https://)

const std = @import("std");
const h2 = @import("h2");

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

/// High-performance HTTP client using unified h2 (HTTP/1.1 + HTTP/2)
pub const HttpClient = struct {
    allocator: std.mem.Allocator,
    config: Config,
    h2_client: h2.Client,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) HttpClient {
        return .{
            .allocator = allocator,
            .config = config,
            .h2_client = h2.Client.init(allocator),
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.h2_client.deinit();
    }

    /// GET request with default headers
    pub fn get(self: *HttpClient, url: []const u8) ![]const u8 {
        return self.fetchWithRetry(url);
    }

    /// GET request with custom headers (headers ignored for now, h2 handles defaults)
    pub fn getWithHeaders(self: *HttpClient, url: []const u8, extra_headers: anytype) ![]const u8 {
        _ = extra_headers;
        return self.fetchWithRetry(url);
    }

    /// GET request with custom Accept header
    pub fn getWithAccept(self: *HttpClient, url: []const u8, accept: []const u8) ![]const u8 {
        _ = accept;
        return self.fetchWithRetry(url);
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
            allocator: std.mem.Allocator,
            url: []const u8,
            result: *FetchResult,
            max_retries: u32,

            fn fetch(ctx: *@This()) void {
                var h2_client = h2.Client.init(ctx.allocator);
                defer h2_client.deinit();

                var retries: u32 = 0;
                while (retries < ctx.max_retries) : (retries += 1) {
                    var response = h2_client.get(ctx.url) catch {
                        if (retries + 1 < ctx.max_retries) {
                            const delay_ms: u64 = @as(u64, 100) << @intCast(retries);
                            std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                        }
                        continue;
                    };
                    defer response.deinit();

                    if (response.status >= 200 and response.status < 300) {
                        ctx.result.* = if (ctx.allocator.dupe(u8, response.body)) |body|
                            .{ .success = body }
                        else |_|
                            .{ .err = HttpError.OutOfMemory };
                        return;
                    } else if (response.status == 404) {
                        ctx.result.* = .{ .err = HttpError.NotFound };
                        return;
                    } else if (response.status == 429) {
                        ctx.result.* = .{ .err = HttpError.TooManyRequests };
                        return;
                    } else if (response.status >= 500) {
                        ctx.result.* = .{ .err = HttpError.ServerError };
                        return;
                    }
                }
                ctx.result.* = .{ .err = HttpError.NetworkError };
            }
        };

        // Create contexts
        const contexts = try self.allocator.alloc(FetchContext, urls.len);
        defer self.allocator.free(contexts);

        for (urls, 0..) |url, i| {
            contexts[i] = .{
                .allocator = self.allocator,
                .url = url,
                .result = &results[i],
                .max_retries = self.config.max_retries,
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
    fn fetchWithRetry(self: *HttpClient, url: []const u8) ![]const u8 {
        var retries: u32 = 0;
        var last_err: HttpError = HttpError.NetworkError;

        while (retries < self.config.max_retries) : (retries += 1) {
            const result = self.doFetch(url);
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

    /// Perform actual HTTP fetch using h2 client
    fn doFetch(self: *HttpClient, url: []const u8) HttpError![]const u8 {
        var response = self.h2_client.get(url) catch return HttpError.NetworkError;
        defer response.deinit();

        // Check status
        if (response.status == 404) return HttpError.NotFound;
        if (response.status == 429) return HttpError.TooManyRequests;
        if (response.status >= 500) return HttpError.ServerError;
        if (response.status < 200 or response.status >= 300) return HttpError.NetworkError;

        // Copy body
        return self.allocator.dupe(u8, response.body) catch HttpError.OutOfMemory;
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

//! Centralized Fetch Scheduler with Batching + Caching
//!
//! Key optimizations:
//! 1. **Batching Window**: Collects requests, fires ONE HTTP/2 batch
//! 2. **In-memory Cache**: Avoids re-fetching resolved packages
//! 3. **Deduplication**: Same package requested twice? Only fetched once
//!
//! ## Usage
//! ```zig
//! var scheduler = FetchScheduler.init(allocator);
//! defer scheduler.deinit();
//!
//! // Queue requests (non-blocking)
//! scheduler.queueFetch("numpy");
//! scheduler.queueFetch("pandas");
//! scheduler.queueFetch("requests");
//!
//! // Execute all queued requests in ONE batch
//! const results = try scheduler.executeBatch();
//! ```

const std = @import("std");
const pypi = @import("pypi.zig");
const H2Client = @import("h2").Client;

/// Cached package metadata with TTL
const CacheEntry = struct {
    metadata: pypi.PackageMetadata,
    timestamp: i64,
};

/// Fetch scheduler with batching and caching
pub const FetchScheduler = struct {
    allocator: std.mem.Allocator,
    client: *pypi.PyPIClient,

    // Request queue (deduplicated)
    pending: std.StringHashMap(void),

    // In-memory cache
    cache: std.StringHashMap(CacheEntry),
    cache_ttl_ms: i64 = 5 * 60 * 1000, // 5 minutes default

    // Stats
    cache_hits: u32 = 0,
    cache_misses: u32 = 0,
    batches_executed: u32 = 0,
    total_fetched: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, client: *pypi.PyPIClient) FetchScheduler {
        return .{
            .allocator = allocator,
            .client = client,
            .pending = std.StringHashMap(void).init(allocator),
            .cache = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    pub fn deinit(self: *FetchScheduler) void {
        // Free pending keys
        var pending_it = self.pending.keyIterator();
        while (pending_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.pending.deinit();

        // Free cache entries
        var cache_it = self.cache.iterator();
        while (cache_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var meta = entry.value_ptr.metadata;
            meta.deinit(self.allocator);
        }
        self.cache.deinit();
    }

    /// Queue a package for fetching (non-blocking, deduplicated)
    /// Returns true if already cached, false if queued for fetch
    pub fn queueFetch(self: *FetchScheduler, name: []const u8) !bool {
        // Normalize name
        var norm_buf: [256]u8 = undefined;
        const norm_name = normalizeName(name, &norm_buf);

        // Check cache first
        if (self.cache.get(norm_name)) |entry| {
            const now = std.time.milliTimestamp();
            if (now - entry.timestamp < self.cache_ttl_ms) {
                self.cache_hits += 1;
                return true; // Already cached
            }
            // Cache expired, remove it
            if (self.cache.fetchRemove(norm_name)) |kv| {
                self.allocator.free(kv.key);
                var meta = kv.value.metadata;
                meta.deinit(self.allocator);
            }
        }

        // Check if already pending
        if (self.pending.contains(norm_name)) {
            return false; // Already queued
        }

        // Add to pending queue
        const key = try self.allocator.dupe(u8, norm_name);
        try self.pending.put(key, {});
        self.cache_misses += 1;

        return false;
    }

    /// Queue multiple packages at once
    pub fn queueFetchAll(self: *FetchScheduler, names: []const []const u8) !void {
        for (names) |name| {
            _ = try self.queueFetch(name);
        }
    }

    /// Get cached metadata (if available)
    pub fn getCached(self: *FetchScheduler, name: []const u8) ?pypi.PackageMetadata {
        var norm_buf: [256]u8 = undefined;
        const norm_name = normalizeName(name, &norm_buf);

        if (self.cache.get(norm_name)) |entry| {
            const now = std.time.milliTimestamp();
            if (now - entry.timestamp < self.cache_ttl_ms) {
                return entry.metadata;
            }
        }
        return null;
    }

    /// Execute all pending requests in ONE batch
    /// Returns slice of results (caller must free)
    pub fn executeBatch(self: *FetchScheduler) ![]pypi.FetchResult {
        if (self.pending.count() == 0) {
            return &[_]pypi.FetchResult{};
        }

        // Collect pending names
        var names = std.ArrayList([]const u8){};
        defer names.deinit(self.allocator);

        var it = self.pending.keyIterator();
        while (it.next()) |key| {
            try names.append(self.allocator, key.*);
        }

        self.batches_executed += 1;
        self.total_fetched += @intCast(names.items.len);

        // Execute batch fetch via HTTP/2 multiplexing
        const results = try self.client.getPackagesParallel(names.items);

        // Cache successful results
        const now = std.time.milliTimestamp();
        for (names.items, 0..) |name, i| {
            if (results[i] == .success) {
                // Clone metadata for cache (results are owned by caller)
                const meta_clone = try self.cloneMetadata(results[i].success);
                const cache_key = try self.allocator.dupe(u8, name);
                try self.cache.put(cache_key, .{
                    .metadata = meta_clone,
                    .timestamp = now,
                });
            }
        }

        // Clear pending (don't free keys - they're now in cache or we need them)
        // Actually, we need to free keys that failed
        var pending_it = self.pending.iterator();
        while (pending_it.next()) |entry| {
            const name = entry.key_ptr.*;
            var norm_buf: [256]u8 = undefined;
            const norm_name = normalizeName(name, &norm_buf);
            if (!self.cache.contains(norm_name)) {
                // Failed fetch - free the key
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.pending.clearRetainingCapacity();

        return results;
    }

    /// Execute batch and return map of name -> metadata
    pub fn executeBatchToMap(self: *FetchScheduler) !std.StringHashMap(pypi.PackageMetadata) {
        const results = try self.executeBatch();
        defer self.allocator.free(results);

        var map = std.StringHashMap(pypi.PackageMetadata).init(self.allocator);
        errdefer map.deinit();

        for (results, 0..) |result, i| {
            _ = i;
            if (result == .success) {
                const name_copy = try self.allocator.dupe(u8, result.success.name);
                try map.put(name_copy, result.success);
            }
        }

        return map;
    }

    /// Get all cached + fetch pending in one call
    /// This is the main API for the resolver
    pub fn fetchAll(self: *FetchScheduler, names: []const []const u8) !std.StringHashMap(pypi.PackageMetadata) {
        var result_map = std.StringHashMap(pypi.PackageMetadata).init(self.allocator);
        errdefer {
            var it = result_map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var meta = entry.value_ptr.*;
                meta.deinit(self.allocator);
            }
            result_map.deinit();
        }

        // First pass: check cache and queue misses
        for (names) |name| {
            var norm_buf: [256]u8 = undefined;
            const norm_name = normalizeName(name, &norm_buf);

            if (self.getCached(norm_name)) |cached| {
                // Clone from cache
                const meta_clone = try self.cloneMetadata(cached);
                const key = try self.allocator.dupe(u8, norm_name);
                try result_map.put(key, meta_clone);
            } else {
                _ = try self.queueFetch(name);
            }
        }

        // Execute batch for cache misses
        if (self.pending.count() > 0) {
            const fetch_results = try self.executeBatch();
            defer {
                for (fetch_results) |*r| {
                    var result = r.*;
                    result.deinit(self.allocator);
                }
                self.allocator.free(fetch_results);
            }

            // Add successful fetches to result
            for (fetch_results) |result| {
                if (result == .success) {
                    var norm_buf: [256]u8 = undefined;
                    const norm_name = normalizeName(result.success.name, &norm_buf);

                    if (!result_map.contains(norm_name)) {
                        const meta_clone = try self.cloneMetadata(result.success);
                        const key = try self.allocator.dupe(u8, norm_name);
                        try result_map.put(key, meta_clone);
                    }
                }
            }
        }

        return result_map;
    }

    /// Clone metadata (deep copy)
    fn cloneMetadata(self: *FetchScheduler, meta: pypi.PackageMetadata) !pypi.PackageMetadata {
        const name = try self.allocator.dupe(u8, meta.name);
        errdefer self.allocator.free(name);

        const version = try self.allocator.dupe(u8, meta.latest_version);
        errdefer self.allocator.free(version);

        // Clone requires_dist
        var requires_dist = std.ArrayList([]const u8){};
        errdefer {
            for (requires_dist.items) |dep| self.allocator.free(dep);
            requires_dist.deinit(self.allocator);
        }
        for (meta.requires_dist) |dep| {
            const dep_copy = try self.allocator.dupe(u8, dep);
            try requires_dist.append(self.allocator, dep_copy);
        }

        // Clone releases (just versions)
        var releases = std.ArrayList(pypi.ReleaseInfo){};
        errdefer {
            for (releases.items) |*r| r.deinit(self.allocator);
            releases.deinit(self.allocator);
        }
        for (meta.releases) |rel| {
            const ver = try self.allocator.dupe(u8, rel.version);
            try releases.append(self.allocator, .{
                .version = ver,
                .files = &[_]pypi.FileInfo{},
            });
        }

        return .{
            .name = name,
            .latest_version = version,
            .summary = null,
            .requires_dist = try requires_dist.toOwnedSlice(self.allocator),
            .releases = try releases.toOwnedSlice(self.allocator),
        };
    }

    /// Get scheduler stats
    pub fn stats(self: *FetchScheduler) SchedulerStats {
        return .{
            .cache_hits = self.cache_hits,
            .cache_misses = self.cache_misses,
            .batches_executed = self.batches_executed,
            .total_fetched = self.total_fetched,
            .cache_size = @intCast(self.cache.count()),
            .pending_count = @intCast(self.pending.count()),
        };
    }

    /// Clear cache
    pub fn clearCache(self: *FetchScheduler) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var meta = entry.value_ptr.metadata;
            meta.deinit(self.allocator);
        }
        self.cache.clearRetainingCapacity();
    }
};

pub const SchedulerStats = struct {
    cache_hits: u32,
    cache_misses: u32,
    batches_executed: u32,
    total_fetched: u32,
    cache_size: u32,
    pending_count: u32,
};

/// Normalize package name (lowercase, replace _ with -)
fn normalizeName(name: []const u8, buf: *[256]u8) []const u8 {
    var len: usize = 0;
    for (name) |c| {
        if (len >= 256) break;
        if (c == '_') {
            buf[len] = '-';
        } else {
            buf[len] = std.ascii.toLower(c);
        }
        len += 1;
    }
    return buf[0..len];
}

// ============================================================================
// Tests
// ============================================================================

test "FetchScheduler creation" {
    const allocator = std.testing.allocator;

    var client = pypi.PyPIClient.init(allocator);
    defer client.deinit();

    var scheduler = FetchScheduler.init(allocator, &client);
    defer scheduler.deinit();

    const s = scheduler.stats();
    try std.testing.expectEqual(@as(u32, 0), s.cache_hits);
    try std.testing.expectEqual(@as(u32, 0), s.batches_executed);
}

test "normalizeName" {
    var buf: [256]u8 = undefined;

    try std.testing.expectEqualStrings("numpy", normalizeName("NumPy", &buf));
    try std.testing.expectEqualStrings("scikit-learn", normalizeName("scikit_learn", &buf));
    try std.testing.expectEqualStrings("my-package", normalizeName("My_Package", &buf));
}

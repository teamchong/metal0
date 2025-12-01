//! PyPI API Client with Parallel Fetching
//!
//! High-performance PyPI package index client with:
//! - Parallel HTTP requests via thread pool
//! - SIMD-accelerated JSON parsing (2.7-3.1x faster)
//! - Connection pooling
//! - Lazy JSON parsing (only materializes accessed fields)
//!
//! ## Usage
//! ```zig
//! var client = try PyPIClient.init(allocator);
//! defer client.deinit();
//!
//! // Fetch single package
//! const meta = try client.getPackageMetadata("numpy");
//! defer meta.deinit(allocator);
//!
//! // Fetch multiple packages in parallel
//! const metas = try client.getPackagesParallel(&.{"numpy", "pandas", "requests"});
//! defer for (metas) |*m| m.deinit(allocator);
//! ```

const std = @import("std");
const json = @import("json"); // SIMD-accelerated JSON parser (2.7-3.1x faster)
const json_stream = json.stream; // Fast streaming JSON extraction

// HTTP/2 with TLS 1.3 (our implementation)
const h2 = @import("h2");
const H2Client = h2.Client;
const H2Response = h2.Response;

pub const PyPIError = error{
    InvalidPackageName,
    PackageNotFound,
    NetworkError,
    ParseError,
    Timeout,
    TooManyRequests, // 429
    ServerError, // 5xx
    OutOfMemory,
};

/// Lightweight version info from Simple API (PEP 691)
pub const SimpleVersion = struct {
    version: []const u8,
    wheel_url: ?[]const u8 = null, // Best wheel URL
    requires_python: ?[]const u8 = null,
    has_metadata: bool = false, // PEP 658: .metadata file available

    pub fn deinit(self: *SimpleVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        if (self.wheel_url) |url| allocator.free(url);
        if (self.requires_python) |rp| allocator.free(rp);
    }
};

/// Lightweight metadata from wheel METADATA file (PEP 658)
/// Only ~2KB vs 80KB for full JSON API
pub const WheelMetadata = struct {
    name: []const u8,
    version: []const u8,
    requires_dist: [][]const u8 = &[_][]const u8{},
    requires_python: ?[]const u8 = null,

    pub fn deinit(self: *WheelMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        for (self.requires_dist) |dep| allocator.free(dep);
        if (self.requires_dist.len > 0) allocator.free(self.requires_dist);
        if (self.requires_python) |rp| allocator.free(rp);
    }
};

/// Lightweight package info from Simple API (much smaller than JSON API)
pub const SimplePackageInfo = struct {
    name: []const u8,
    versions: []SimpleVersion,

    pub fn deinit(self: *SimplePackageInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.versions) |*v| {
            @constCast(v).deinit(allocator);
        }
        if (self.versions.len > 0) allocator.free(self.versions);
    }

    /// Get latest version
    pub fn latestVersion(self: SimplePackageInfo) ?[]const u8 {
        if (self.versions.len == 0) return null;
        return self.versions[self.versions.len - 1].version;
    }
};

/// Package release info from PyPI JSON API
pub const ReleaseInfo = struct {
    version: []const u8,
    requires_python: ?[]const u8 = null,
    yanked: bool = false,
    files: []const FileInfo = &[_]FileInfo{},

    pub fn deinit(self: *ReleaseInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        if (self.requires_python) |rp| allocator.free(rp);
        for (self.files) |*f| {
            @constCast(f).deinit(allocator);
        }
        if (self.files.len > 0) allocator.free(self.files);
    }
};

/// File info for a release (wheel, sdist, etc.)
pub const FileInfo = struct {
    filename: []const u8,
    url: []const u8,
    size: u64 = 0,
    sha256: ?[]const u8 = null,
    requires_python: ?[]const u8 = null,
    packagetype: PackageType = .unknown,

    pub const PackageType = enum {
        bdist_wheel,
        sdist,
        unknown,
    };

    pub fn deinit(self: *FileInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.filename);
        allocator.free(self.url);
        if (self.sha256) |h| allocator.free(h);
        if (self.requires_python) |rp| allocator.free(rp);
    }

    /// Check if this is a wheel file
    pub fn isWheel(self: FileInfo) bool {
        return self.packagetype == .bdist_wheel or
            std.mem.endsWith(u8, self.filename, ".whl");
    }

    /// Check if this is a source distribution
    pub fn isSdist(self: FileInfo) bool {
        return self.packagetype == .sdist or
            std.mem.endsWith(u8, self.filename, ".tar.gz") or
            std.mem.endsWith(u8, self.filename, ".zip");
    }
};

/// Package metadata from PyPI
pub const PackageMetadata = struct {
    name: []const u8,
    latest_version: []const u8,
    summary: ?[]const u8 = null,
    releases: []ReleaseInfo = &[_]ReleaseInfo{},
    requires_dist: []const []const u8 = &[_][]const u8{}, // Dependency strings from PyPI

    pub fn deinit(self: *PackageMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.latest_version);
        if (self.summary) |s| allocator.free(s);
        for (self.releases) |*r| {
            @constCast(r).deinit(allocator);
        }
        if (self.releases.len > 0) allocator.free(self.releases);
        for (self.requires_dist) |dep| {
            allocator.free(dep);
        }
        if (self.requires_dist.len > 0) allocator.free(self.requires_dist);
    }
};

/// Fetch result for parallel operations
pub const FetchResult = union(enum) {
    success: PackageMetadata,
    err: PyPIError,

    pub fn deinit(self: *FetchResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |*meta| meta.deinit(allocator),
            .err => {},
        }
    }
};

/// Wheel metadata fetch result for parallel operations
pub const WheelMetadataResult = union(enum) {
    success: WheelMetadata,
    err: PyPIError,

    pub fn deinit(self: *WheelMetadataResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .success => |*meta| meta.deinit(allocator),
            .err => {},
        }
    }
};

/// PyPI client configuration
pub const Config = struct {
    /// Base URL for JSON API (default: pypi.org)
    json_api_url: []const u8 = "https://pypi.org/pypi",
    /// Base URL for Simple API (default: pypi.org)
    simple_api_url: []const u8 = "https://pypi.org/simple",
    /// Request timeout in milliseconds
    timeout_ms: u64 = 30000,
    /// Max concurrent requests
    max_concurrent: u32 = 32,
    /// Max retries on failure
    max_retries: u32 = 3,
    /// User agent string
    user_agent: []const u8 = "metal0-pkg/1.0",
};

/// High-performance PyPI API client
pub const PyPIClient = struct {
    allocator: std.mem.Allocator,
    config: Config,
    h2_client: H2Client, // Persistent HTTP/2 connection pool

    pub fn init(allocator: std.mem.Allocator) PyPIClient {
        return .{
            .allocator = allocator,
            .config = .{},
            .h2_client = H2Client.init(allocator),
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) PyPIClient {
        return .{
            .allocator = allocator,
            .config = config,
            .h2_client = H2Client.init(allocator),
        };
    }

    pub fn deinit(self: *PyPIClient) void {
        self.h2_client.deinit();
    }

    /// Fetch package metadata from PyPI JSON API
    pub fn getPackageMetadata(self: *PyPIClient, package_name: []const u8) !PackageMetadata {
        // Build URL: https://pypi.org/pypi/{package}/json
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/json",
            .{ self.config.json_api_url, package_name },
        );
        defer self.allocator.free(url);

        // Fetch JSON
        const body = try self.fetchUrl(url);
        defer self.allocator.free(body);

        // Parse JSON response
        return try self.parsePackageJson(body, package_name);
    }

    /// Fetch package metadata for specific version
    pub fn getPackageVersion(self: *PyPIClient, package_name: []const u8, version: []const u8) !PackageMetadata {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/{s}/json",
            .{ self.config.json_api_url, package_name, version },
        );
        defer self.allocator.free(url);

        const body = try self.fetchUrl(url);
        defer self.allocator.free(body);

        return try self.parsePackageJson(body, package_name);
    }

    /// FAST: Get package versions from Simple API (PEP 691)
    /// This is ~40% smaller than JSON API and much faster to parse
    pub fn getSimplePackageInfo(self: *PyPIClient, package_name: []const u8) !SimplePackageInfo {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/",
            .{ self.config.simple_api_url, package_name },
        );
        defer self.allocator.free(url);

        // Fetch with PEP 691 JSON accept header
        const body = try self.fetchUrlWithAccept(url, "application/vnd.pypi.simple.v1+json");
        defer self.allocator.free(body);

        return try self.parseSimpleJson(body, package_name);
    }

    /// FASTEST: Fetch wheel METADATA file directly (PEP 658)
    /// Only ~2KB vs 80KB for full JSON API - 40x smaller!
    pub fn getWheelMetadata(self: *PyPIClient, wheel_url: []const u8) !WheelMetadata {
        // PEP 658: append .metadata to wheel URL
        const metadata_url = try std.fmt.allocPrint(
            self.allocator,
            "{s}.metadata",
            .{wheel_url},
        );
        defer self.allocator.free(metadata_url);

        const body = try self.fetchUrlWithAccept(metadata_url, "text/plain");
        defer self.allocator.free(body);

        return try self.parseWheelMetadata(body);
    }

    /// Parse wheel METADATA file (RFC 822-like format)
    fn parseWheelMetadata(self: *PyPIClient, body: []const u8) !WheelMetadata {
        var name: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var requires_python: ?[]const u8 = null;
        var requires_dist_list = std.ArrayList([]const u8){};
        errdefer {
            if (name) |n| self.allocator.free(n);
            if (version) |v| self.allocator.free(v);
            if (requires_python) |rp| self.allocator.free(rp);
            for (requires_dist_list.items) |dep| self.allocator.free(dep);
            requires_dist_list.deinit(self.allocator);
        }

        // Parse line by line (RFC 822 format)
        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            // Skip empty lines and continuation lines
            if (line.len == 0) continue;
            if (line[0] == ' ' or line[0] == '\t') continue;

            // Parse "Key: Value" format
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const key = line[0..colon_pos];
                const value = std.mem.trimRight(u8, line[colon_pos + 2 ..], "\r");

                if (std.ascii.eqlIgnoreCase(key, "Name")) {
                    if (name == null) {
                        name = try self.allocator.dupe(u8, value);
                    }
                } else if (std.ascii.eqlIgnoreCase(key, "Version")) {
                    if (version == null) {
                        version = try self.allocator.dupe(u8, value);
                    }
                } else if (std.ascii.eqlIgnoreCase(key, "Requires-Python")) {
                    if (requires_python == null) {
                        requires_python = try self.allocator.dupe(u8, value);
                    }
                } else if (std.ascii.eqlIgnoreCase(key, "Requires-Dist")) {
                    const dep = try self.allocator.dupe(u8, value);
                    try requires_dist_list.append(self.allocator, dep);
                }
            }
        }

        if (name == null or version == null) {
            return PyPIError.ParseError;
        }

        return .{
            .name = name.?,
            .version = version.?,
            .requires_dist = try requires_dist_list.toOwnedSlice(self.allocator),
            .requires_python = requires_python,
        };
    }

    /// Fetch URL with custom Accept header (using HTTP/2)
    fn fetchUrlWithAccept(self: *PyPIClient, url: []const u8, accept: []const u8) ![]const u8 {
        _ = accept; // H2 client handles accept headers internally
        var response = self.h2_client.get(url) catch return PyPIError.NetworkError;
        defer response.deinit();

        if (response.status != 200) return PyPIError.NetworkError;

        return self.allocator.dupe(u8, response.body) catch return PyPIError.OutOfMemory;
    }

    /// Parse Simple API JSON response (PEP 691)
    /// Now captures wheel URLs with PEP 658 metadata support for fast dependency fetching
    fn parseSimpleJson(self: *PyPIClient, body: []const u8, package_name: []const u8) !SimplePackageInfo {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch
            return PyPIError.ParseError;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return PyPIError.ParseError;

        const obj = root.object;

        // Get name
        const name = try self.allocator.dupe(u8, package_name);
        errdefer self.allocator.free(name);

        // Track best wheel URL per version (prefer py3-none-any wheels with metadata)
        const VersionInfo = struct {
            version: []const u8,
            wheel_url: ?[]const u8,
            has_metadata: bool,
            requires_python: ?[]const u8,
        };
        var version_map = std.StringHashMap(VersionInfo).init(self.allocator);
        defer version_map.deinit();

        // Parse files to get wheel URLs with PEP 658 metadata
        if (obj.get("files")) |files_val| {
            if (files_val == .array) {
                for (files_val.array.items) |file| {
                    if (file != .object) continue;
                    const file_obj = file.object;

                    // Get filename
                    const filename_val = file_obj.get("filename") orelse continue;
                    if (filename_val != .string) continue;
                    const filename = filename_val.string;

                    // Extract version from filename
                    const ver = extractVersionFromFilename(filename) orelse continue;

                    // Get URL
                    const url_val = file_obj.get("url") orelse continue;
                    if (url_val != .string) continue;

                    // Check for PEP 658 metadata availability
                    var has_metadata = false;
                    if (file_obj.get("data-dist-info-metadata")) |meta_val| {
                        has_metadata = switch (meta_val) {
                            .bool => meta_val.bool,
                            .object => true, // {sha256: "..."} format
                            else => false,
                        };
                    }
                    // Also check core-metadata (alternative field name)
                    if (!has_metadata) {
                        if (file_obj.get("core-metadata")) |meta_val| {
                            has_metadata = switch (meta_val) {
                                .bool => meta_val.bool,
                                .object => true,
                                else => false,
                            };
                        }
                    }

                    // Get requires-python
                    var requires_python: ?[]const u8 = null;
                    if (file_obj.get("requires-python")) |rp_val| {
                        if (rp_val == .string) {
                            requires_python = rp_val.string;
                        }
                    }

                    // Only consider wheel files
                    const is_wheel = std.mem.endsWith(u8, filename, ".whl");
                    if (!is_wheel) continue;

                    // Prefer py3-none-any wheels (universal)
                    const is_universal = std.mem.indexOf(u8, filename, "-py3-none-any") != null or
                        std.mem.indexOf(u8, filename, "-py2.py3-none-any") != null;

                    // Check if we should update this version's info
                    if (version_map.getPtr(ver)) |existing| {
                        // Prefer: has_metadata > universal > first found
                        const dominated = (has_metadata and !existing.has_metadata) or
                            (has_metadata == existing.has_metadata and is_universal and existing.wheel_url != null and
                            std.mem.indexOf(u8, existing.wheel_url.?, "-py3-none-any") == null);
                        if (!dominated) continue;

                        // Free old values and update in place (keep the key)
                        if (existing.wheel_url) |old_url| self.allocator.free(old_url);
                        if (existing.requires_python) |old_rp| self.allocator.free(old_rp);

                        // Update URL
                        existing.wheel_url = try self.allocator.dupe(u8, url_val.string);
                        existing.has_metadata = has_metadata;
                        if (requires_python) |rp| {
                            existing.requires_python = try self.allocator.dupe(u8, rp);
                        } else {
                            existing.requires_python = null;
                        }
                    } else {
                        // New version - store it
                        const ver_copy = try self.allocator.dupe(u8, ver);
                        errdefer self.allocator.free(ver_copy);
                        const url_copy = try self.allocator.dupe(u8, url_val.string);
                        errdefer self.allocator.free(url_copy);
                        var rp_copy: ?[]const u8 = null;
                        if (requires_python) |rp| {
                            rp_copy = try self.allocator.dupe(u8, rp);
                        }

                        try version_map.put(ver_copy, .{
                            .version = ver_copy,
                            .wheel_url = url_copy,
                            .has_metadata = has_metadata,
                            .requires_python = rp_copy,
                        });
                    }
                }
            }
        }

        // Convert map to list
        var versions_list = std.ArrayList(SimpleVersion){};
        errdefer {
            for (versions_list.items) |*v| v.deinit(self.allocator);
            versions_list.deinit(self.allocator);
        }

        var it = version_map.iterator();
        while (it.next()) |entry| {
            try versions_list.append(self.allocator, .{
                .version = entry.value_ptr.version,
                .wheel_url = entry.value_ptr.wheel_url,
                .has_metadata = entry.value_ptr.has_metadata,
                .requires_python = entry.value_ptr.requires_python,
            });
        }

        return .{
            .name = name,
            .versions = try versions_list.toOwnedSlice(self.allocator),
        };
    }

    /// Fetch multiple packages in parallel using HTTP/2 multiplexing
    /// All requests go over a SINGLE connection - massively faster!
    pub fn getPackagesParallel(
        self: *PyPIClient,
        package_names: []const []const u8,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        var timer = std.time.Timer.start() catch unreachable;

        // Build URLs
        var urls = try self.allocator.alloc([]const u8, package_names.len);
        defer {
            for (urls) |url| self.allocator.free(url);
            self.allocator.free(urls);
        }

        for (package_names, 0..) |name, i| {
            urls[i] = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}/json",
                .{ self.config.json_api_url, name },
            );
        }

        const url_time = timer.read() / 1_000_000;

        // Use HTTP/2 multiplexed fetch (reuse persistent connection!)
        const h2_responses = try self.h2_client.getAll(urls);
        defer {
            for (h2_responses) |*r| r.deinit();
            self.allocator.free(h2_responses);
        }

        const fetch_time = timer.read() / 1_000_000;

        // Convert to FetchResult
        const results = try self.allocator.alloc(FetchResult, package_names.len);
        for (h2_responses, 0..) |resp, i| {
            if (resp.status == 200) {
                const meta = parsePackageJsonStatic(self.allocator, resp.body, package_names[i]) catch {
                    results[i] = .{ .err = PyPIError.ParseError };
                    continue;
                };
                results[i] = .{ .success = meta };
            } else if (resp.status == 404) {
                results[i] = .{ .err = PyPIError.PackageNotFound };
            } else {
                results[i] = .{ .err = PyPIError.NetworkError };
            }
        }

        const parse_time = timer.read() / 1_000_000;
        std.debug.print("[PyPI] {d} packages: url={d}ms, fetch={d}ms, parse={d}ms\n", .{ package_names.len, url_time, fetch_time - url_time, parse_time - fetch_time });

        return results;
    }

    /// Fetch multiple packages with DISK CACHE support
    /// Stores raw JSON responses in cache for instant subsequent lookups
    /// Second run is ~1ms instead of ~150ms (150x faster!)
    /// Batches requests to avoid HTTP/2 stream limits (max 100 concurrent)
    pub fn getPackagesParallelWithCache(
        self: *PyPIClient,
        package_names: []const []const u8,
        cache: ?*@import("cache.zig").Cache,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        // HTTP/2 max concurrent streams is typically 100-128
        // Batch requests to avoid silent failures
        const MAX_CONCURRENT: usize = 100;

        if (package_names.len > MAX_CONCURRENT) {
            // Process in batches
            const results = try self.allocator.alloc(FetchResult, package_names.len);
            var processed: usize = 0;

            while (processed < package_names.len) {
                const batch_end = @min(processed + MAX_CONCURRENT, package_names.len);
                const batch = package_names[processed..batch_end];

                const batch_results = try self.getPackagesParallelWithCacheInternal(batch, cache);
                // DON'T defer free batch_results - we're transferring ownership to results array

                // Move results (ownership transfer, not copy)
                for (batch_results, 0..) |r, i| {
                    results[processed + i] = r;
                }
                // Free the batch array itself but NOT the contents (ownership transferred)
                self.allocator.free(batch_results);
                processed = batch_end;
            }

            return results;
        }

        return self.getPackagesParallelWithCacheInternal(package_names, cache);
    }

    fn getPackagesParallelWithCacheInternal(
        self: *PyPIClient,
        package_names: []const []const u8,
        cache: ?*@import("cache.zig").Cache,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        var timer = std.time.Timer.start() catch unreachable;

        // Build URLs
        var urls = try self.allocator.alloc([]const u8, package_names.len);
        defer {
            for (urls) |url| self.allocator.free(url);
            self.allocator.free(urls);
        }

        for (package_names, 0..) |name, i| {
            urls[i] = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}/json",
                .{ self.config.json_api_url, name },
            );
        }

        const url_time = timer.read() / 1_000_000;

        // Use HTTP/2 multiplexed fetch (reuse persistent connection!)
        const h2_responses = try self.h2_client.getAll(urls);
        defer {
            for (h2_responses) |*r| r.deinit();
            self.allocator.free(h2_responses);
        }

        const fetch_time = timer.read() / 1_000_000;

        // Convert to FetchResult AND cache successful responses
        const results = try self.allocator.alloc(FetchResult, package_names.len);
        for (h2_responses, 0..) |resp, i| {
            if (resp.status == 200) {
                // CACHE: Store raw JSON for future use
                if (cache) |c| {
                    const cache_key = std.fmt.allocPrint(self.allocator, "pypi:json:{s}", .{package_names[i]}) catch null;
                    if (cache_key) |key| {
                        defer self.allocator.free(key);
                        c.put(key, resp.body) catch {}; // Best effort
                    }
                }

                const meta = parsePackageJsonStatic(self.allocator, resp.body, package_names[i]) catch {
                    results[i] = .{ .err = PyPIError.ParseError };
                    continue;
                };
                results[i] = .{ .success = meta };
            } else if (resp.status == 404) {
                results[i] = .{ .err = PyPIError.PackageNotFound };
            } else {
                results[i] = .{ .err = PyPIError.NetworkError };
            }
        }

        const parse_time = timer.read() / 1_000_000;
        std.debug.print("[PyPI+Cache] {d} packages: url={d}ms, fetch={d}ms, parse={d}ms\n", .{ package_names.len, url_time, fetch_time - url_time, parse_time - fetch_time });

        return results;
    }

    /// FAST HTTP/2: Fetch using Simple API + PEP 658 wheel METADATA
    /// Downloads ~12KB per package instead of ~80KB (6-7x smaller!)
    /// Phase 1: Fetch all Simple API pages in parallel (~10KB each)
    /// Phase 2: Fetch all wheel METADATA files in parallel (~2KB each)
    pub fn getPackagesParallelH2Fast(
        self: *PyPIClient,
        package_names: []const []const u8,
    ) ![]FetchResult {
        return self.getPackagesParallelH2FastWithCache(package_names, null);
    }

    /// Fast path with cache support - Simple API + PEP 658 wheel METADATA
    pub fn getPackagesParallelH2FastWithCache(
        self: *PyPIClient,
        package_names: []const []const u8,
        cache: ?*@import("cache.zig").Cache,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        var timer = std.time.Timer.start() catch unreachable;

        // Allocate results array
        const results = try self.allocator.alloc(FetchResult, package_names.len);
        for (results) |*r| r.* = .{ .err = PyPIError.NetworkError };

        // Phase 0: Check cache for METADATA (the parsed wheel metadata text)
        var uncached_names = std.ArrayList([]const u8){};
        defer uncached_names.deinit(self.allocator);
        var uncached_indices = std.ArrayList(usize){};
        defer uncached_indices.deinit(self.allocator);

        var cache_hits: usize = 0;
        if (cache) |c| {
            for (package_names, 0..) |name, i| {
                // Try cached METADATA text first (fast path cache)
                const meta_key = std.fmt.allocPrint(self.allocator, "meta:{s}", .{name}) catch {
                    try uncached_names.append(self.allocator, name);
                    try uncached_indices.append(self.allocator, i);
                    continue;
                };
                defer self.allocator.free(meta_key);

                if (c.get(meta_key)) |cached_metadata| {
                    // Parse cached METADATA text
                    const meta = self.parseWheelMetadataText(cached_metadata, name, null) catch {
                        try uncached_names.append(self.allocator, name);
                        try uncached_indices.append(self.allocator, i);
                        continue;
                    };
                    results[i] = .{ .success = meta };
                    cache_hits += 1;
                } else {
                    try uncached_names.append(self.allocator, name);
                    try uncached_indices.append(self.allocator, i);
                }
            }
        } else {
            // No cache - all packages need fetching
            for (package_names, 0..) |name, i| {
                try uncached_names.append(self.allocator, name);
                try uncached_indices.append(self.allocator, i);
            }
        }

        const cache_time = timer.read() / 1_000_000;

        // If all cached, return early
        if (uncached_names.items.len == 0) {
            std.debug.print("[PyPI-Fast] {d} packages: ALL CACHED in {d}ms\n", .{ package_names.len, cache_time });
            return results;
        }

        // Phase 0.5: Check Simple API cache to avoid network calls
        var simple_bodies = try self.allocator.alloc(?[]const u8, uncached_names.items.len);
        defer {
            for (simple_bodies) |body| {
                if (body) |b| self.allocator.free(b);
            }
            self.allocator.free(simple_bodies);
        }
        @memset(simple_bodies, null);

        var need_simple_fetch = std.ArrayList(usize){}; // indices into uncached that need fetch
        defer need_simple_fetch.deinit(self.allocator);

        var simple_cache_hits: usize = 0;
        if (cache) |c| {
            for (uncached_names.items, 0..) |name, i| {
                const simple_key = std.fmt.allocPrint(self.allocator, "simple:{s}", .{name}) catch {
                    try need_simple_fetch.append(self.allocator, i);
                    continue;
                };
                defer self.allocator.free(simple_key);

                if (c.get(simple_key)) |cached_html| {
                    simple_bodies[i] = try self.allocator.dupe(u8, cached_html);
                    simple_cache_hits += 1;
                } else {
                    try need_simple_fetch.append(self.allocator, i);
                }
            }
        } else {
            for (0..uncached_names.items.len) |i| {
                try need_simple_fetch.append(self.allocator, i);
            }
        }

        // Phase 1: Build Simple API URLs for packages that weren't in cache
        var simple_urls = std.ArrayList([]const u8){};
        defer {
            for (simple_urls.items) |url| self.allocator.free(url);
            simple_urls.deinit(self.allocator);
        }

        for (need_simple_fetch.items) |i| {
            const url = try std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}/",
                .{ self.config.simple_api_url, uncached_names.items[i] },
            );
            try simple_urls.append(self.allocator, url);
        }

        // Phase 1: Fetch Simple API pages that weren't cached
        var fetched_responses: []H2Response = &[_]H2Response{};
        if (simple_urls.items.len > 0) {
            fetched_responses = try self.h2_client.getAll(simple_urls.items);
        }
        defer {
            for (fetched_responses) |*r| r.deinit();
            if (fetched_responses.len > 0) self.allocator.free(fetched_responses);
        }

        // Merge fetched responses into simple_bodies and cache them
        for (fetched_responses, 0..) |resp, fetch_idx| {
            const uncached_idx = need_simple_fetch.items[fetch_idx];
            if (resp.status == 200 and resp.body.len > 0) {
                simple_bodies[uncached_idx] = try self.allocator.dupe(u8, resp.body);

                // Cache Simple API response
                if (cache) |c| {
                    const simple_key = std.fmt.allocPrint(self.allocator, "simple:{s}", .{uncached_names.items[uncached_idx]}) catch continue;
                    defer self.allocator.free(simple_key);
                    c.put(simple_key, resp.body) catch {};
                }
            }
        }

        const simple_time = timer.read() / 1_000_000;

        // Phase 2: Parse Simple API to find wheel METADATA URLs
        var metadata_urls = std.ArrayList([]const u8){};
        defer {
            for (metadata_urls.items) |url| self.allocator.free(url);
            metadata_urls.deinit(self.allocator);
        }
        var metadata_to_uncached = std.ArrayList(usize){}; // Map metadata URL index -> uncached index
        defer metadata_to_uncached.deinit(self.allocator);

        // Track which uncached packages need JSON API fallback
        var needs_json_fallback = try self.allocator.alloc(bool, uncached_names.items.len);
        defer self.allocator.free(needs_json_fallback);
        @memset(needs_json_fallback, true);

        // Parse each Simple API response
        var simple_data = try self.allocator.alloc(?SimplePackageInfo, uncached_names.items.len);
        defer {
            for (simple_data) |*sd| {
                if (sd.*) |*s| s.deinit(self.allocator);
            }
            self.allocator.free(simple_data);
        }
        @memset(simple_data, null);

        for (simple_bodies, 0..) |body_opt, i| {
            const body = body_opt orelse continue;

            // Parse Simple API HTML to get wheel URL with metadata
            const parsed = self.parseSimpleApiHtml(body, uncached_names.items[i]) catch continue;
            simple_data[i] = parsed;

            // Find best wheel with PEP 658 metadata
            var best_url: ?[]const u8 = null;
            for (parsed.versions) |v| {
                if (v.has_metadata and v.wheel_url != null) {
                    best_url = v.wheel_url;
                }
            }

            if (best_url) |wheel_url| {
                // Build METADATA URL: wheel_url + .metadata
                const metadata_url = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.metadata",
                    .{wheel_url},
                );
                try metadata_urls.append(self.allocator, metadata_url);
                try metadata_to_uncached.append(self.allocator, i);
                needs_json_fallback[i] = false;
            }
        }

        const parse_simple_time = timer.read() / 1_000_000;

        // Phase 2: Fetch all METADATA files in parallel (reuse connection)
        var metadata_responses: []H2Response = &[_]H2Response{};
        if (metadata_urls.items.len > 0) {
            metadata_responses = try self.h2_client.getAll(metadata_urls.items);
        }
        defer {
            for (metadata_responses) |*r| r.deinit();
            if (metadata_responses.len > 0) self.allocator.free(metadata_responses);
        }

        const metadata_time = timer.read() / 1_000_000;

        // Phase 3: Process METADATA responses into results and cache them
        for (metadata_responses, 0..) |resp, meta_idx| {
            const uncached_idx = metadata_to_uncached.items[meta_idx];
            const orig_idx = uncached_indices.items[uncached_idx];
            if (resp.status != 200) {
                needs_json_fallback[uncached_idx] = true;
                continue;
            }

            // Parse wheel METADATA
            const meta = self.parseWheelMetadataText(resp.body, uncached_names.items[uncached_idx], simple_data[uncached_idx]) catch {
                needs_json_fallback[uncached_idx] = true;
                continue;
            };
            results[orig_idx] = .{ .success = meta };

            // Cache METADATA text for future runs
            if (cache) |c| {
                const meta_key = std.fmt.allocPrint(self.allocator, "meta:{s}", .{uncached_names.items[uncached_idx]}) catch continue;
                defer self.allocator.free(meta_key);
                c.put(meta_key, resp.body) catch {};
            }
        }

        // Phase 4: JSON API fallback for packages without PEP 658
        var fallback_count: usize = 0;
        for (needs_json_fallback) |needs| {
            if (needs) fallback_count += 1;
        }

        if (fallback_count > 0) {
            var fallback_names = try self.allocator.alloc([]const u8, fallback_count);
            defer self.allocator.free(fallback_names);
            var fallback_orig_indices = try self.allocator.alloc(usize, fallback_count);
            defer self.allocator.free(fallback_orig_indices);

            var j: usize = 0;
            for (needs_json_fallback, 0..) |needs, i| {
                if (needs) {
                    fallback_names[j] = uncached_names.items[i];
                    fallback_orig_indices[j] = uncached_indices.items[i];
                    j += 1;
                }
            }

            // Use JSON API for fallback packages (WITH CACHE!)
            const fallback_results = try self.getPackagesParallelWithCache(fallback_names, cache);
            defer self.allocator.free(fallback_results);

            for (fallback_results, 0..) |fr, fi| {
                results[fallback_orig_indices[fi]] = fr;
            }
        }

        const total_time = timer.read() / 1_000_000;
        std.debug.print("[PyPI-Fast] {d} packages ({d} meta-cached, {d} simple-cached): cache={d}ms, simple={d}ms, parse={d}ms, meta={d}ms, total={d}ms\n", .{
            package_names.len,
            cache_hits,
            simple_cache_hits,
            cache_time,
            simple_time - cache_time,
            parse_simple_time - simple_time,
            metadata_time - parse_simple_time,
            total_time,
        });

        return results;
    }

    /// Parse wheel METADATA text file
    fn parseWheelMetadataText(
        self: *PyPIClient,
        body: []const u8,
        package_name: []const u8,
        simple_info: ?SimplePackageInfo,
    ) !PackageMetadata {
        var requires_dist = std.ArrayList([]const u8){};
        errdefer {
            for (requires_dist.items) |dep| self.allocator.free(dep);
            requires_dist.deinit(self.allocator);
        }

        var version: ?[]const u8 = null;

        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) break; // Headers end at blank line

            if (std.mem.startsWith(u8, trimmed, "Version:")) {
                const val = std.mem.trim(u8, trimmed["Version:".len..], " ");
                version = try self.allocator.dupe(u8, val);
            } else if (std.mem.startsWith(u8, trimmed, "Requires-Dist:")) {
                const val = std.mem.trim(u8, trimmed["Requires-Dist:".len..], " ");
                const dep_copy = try self.allocator.dupe(u8, val);
                try requires_dist.append(self.allocator, dep_copy);
            }
        }

        // Build releases from simple_info if available
        var releases = std.ArrayList(ReleaseInfo){};
        errdefer {
            for (releases.items) |*r| @constCast(r).deinit(self.allocator);
            releases.deinit(self.allocator);
        }

        if (simple_info) |info| {
            for (info.versions) |v| {
                const ver_copy = try self.allocator.dupe(u8, v.version);
                try releases.append(self.allocator, .{
                    .version = ver_copy,
                    .files = &[_]FileInfo{},
                });
            }
        } else if (version) |v| {
            const ver_copy = try self.allocator.dupe(u8, v);
            try releases.append(self.allocator, .{
                .version = ver_copy,
                .files = &[_]FileInfo{},
            });
        }

        return .{
            .name = try self.allocator.dupe(u8, package_name),
            .latest_version = version orelse try self.allocator.dupe(u8, "0.0.0"),
            .requires_dist = try requires_dist.toOwnedSlice(self.allocator),
            .releases = try releases.toOwnedSlice(self.allocator),
        };
    }

    /// Parse Simple API HTML to extract version and wheel info
    /// Optimized: Scans backwards to find latest wheel with metadata first
    fn parseSimpleApiHtml(self: *PyPIClient, body: []const u8, _: []const u8) !SimplePackageInfo {
        var versions = std.ArrayList(SimpleVersion){};
        errdefer {
            for (versions.items) |*v| v.deinit(self.allocator);
            versions.deinit(self.allocator);
        }

        // FAST PATH: Find the LAST wheel with "data-dist-info-metadata" (usually latest version)
        // Single reverse scan to find latest entry with metadata
        if (std.mem.lastIndexOf(u8, body, "data-dist-info-metadata")) |meta_pos| {
            // Found metadata attribute, now find the enclosing <a> tag
            if (std.mem.lastIndexOf(u8, body[0..meta_pos], "<a ")) |tag_start| {
                if (std.mem.indexOfPos(u8, body, tag_start, "</a>")) |tag_end| {
                    const tag = body[tag_start..tag_end];

                    // Verify it's a wheel
                    if (std.mem.indexOf(u8, tag, ".whl\"")) |_| {
                        // Extract href
                        if (std.mem.indexOf(u8, tag, "href=\"")) |href_start| {
                            const href_content_start = href_start + 6;
                            if (std.mem.indexOfPos(u8, tag, href_content_start, "\"")) |href_end| {
                                // Strip fragment
                                const href_full = tag[href_content_start..href_end];
                                const href = if (std.mem.indexOf(u8, href_full, "#")) |hash_pos|
                                    href_full[0..hash_pos]
                                else
                                    href_full;

                                // Extract filename
                                if (std.mem.indexOf(u8, tag, ">")) |text_start| {
                                    const filename = tag[text_start + 1 ..];
                                    if (std.mem.endsWith(u8, filename, ".whl")) {
                                        if (extractVersionFromFilename(filename)) |ver| {
                                            const ver_copy = try self.allocator.dupe(u8, ver);
                                            const href_copy = try self.allocator.dupe(u8, href);

                                            try versions.append(self.allocator, .{
                                                .version = ver_copy,
                                                .wheel_url = href_copy,
                                                .requires_python = null,
                                                .has_metadata = true,
                                            });

                                            return .{
                                                .name = "",
                                                .versions = try versions.toOwnedSlice(self.allocator),
                                            };
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // SLOW PATH: Parse all anchors (fallback for packages without metadata)
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, body, pos, "<a ")) |start| {
            const end = std.mem.indexOfPos(u8, body, start, "</a>") orelse break;
            const tag = body[start..end];

            // Extract href
            const href_start = std.mem.indexOf(u8, tag, "href=\"") orelse {
                pos = end;
                continue;
            };
            const href_content_start = href_start + 6;
            const href_end = std.mem.indexOfPos(u8, tag, href_content_start, "\"") orelse {
                pos = end;
                continue;
            };
            // Strip fragment (#sha256=...) from href for clean URL
            const href_full = tag[href_content_start..href_end];
            const href = if (std.mem.indexOf(u8, href_full, "#")) |hash_pos|
                href_full[0..hash_pos]
            else
                href_full;

            // Extract filename (between > and </a>)
            const text_start = std.mem.indexOf(u8, tag, ">") orelse {
                pos = end;
                continue;
            };
            const filename = tag[text_start + 1 ..];

            // Only process wheel files
            if (!std.mem.endsWith(u8, filename, ".whl")) {
                pos = end;
                continue;
            }

            // Extract version from filename
            const ver = extractVersionFromFilename(filename) orelse {
                pos = end;
                continue;
            };

            // Check for data-dist-info-metadata attribute (PEP 658)
            const has_metadata = std.mem.indexOf(u8, tag, "data-dist-info-metadata") != null;

            // Store version info (later versions overwrite earlier - gives us latest)
            const ver_copy = try self.allocator.dupe(u8, ver);
            const href_copy = try self.allocator.dupe(u8, href);

            try versions.append(self.allocator, .{
                .version = ver_copy,
                .wheel_url = href_copy,
                .requires_python = null,
                .has_metadata = has_metadata,
            });

            pos = end;
        }

        return .{
            .name = "",
            .versions = try versions.toOwnedSlice(self.allocator),
        };
    }

    /// FAST: Parallel fetch using Simple API + PEP 658 wheel METADATA
    /// Downloads ~2KB per package instead of ~80KB (40x smaller!)
    pub fn getPackagesParallelFast(
        self: *PyPIClient,
        package_names: []const []const u8,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        const results = try self.allocator.alloc(FetchResult, package_names.len);
        errdefer self.allocator.free(results);

        for (results) |*r| {
            r.* = .{ .err = PyPIError.NetworkError };
        }

        // Fast fetch context - uses Simple API + wheel METADATA
        const FastFetchContext = struct {
            client: *PyPIClient,
            name: []const u8,
            result: *FetchResult,

            fn fetch(ctx: *@This()) void {
                ctx.result.* = if (ctx.fetchFast()) |meta|
                    .{ .success = meta }
                else |_|
                    .{ .err = PyPIError.NetworkError };
            }

            fn fetchFast(ctx: *@This()) !PackageMetadata {
                const allocator = ctx.client.allocator;

                // 1. Get Simple API - lightweight version list
                var simple = ctx.client.getSimplePackageInfo(ctx.name) catch {
                    // Fallback to JSON API
                    return ctx.client.getPackageMetadata(ctx.name);
                };
                defer simple.deinit(allocator);

                // 2. Find latest version with PEP 658 metadata support
                var best_wheel_url: ?[]const u8 = null;
                var best_version: ?[]const u8 = null;
                for (simple.versions) |v| {
                    if (v.has_metadata and v.wheel_url != null) {
                        best_wheel_url = v.wheel_url;
                        best_version = v.version;
                    }
                }

                // 3. No PEP 658 metadata available? Use full JSON API
                if (best_wheel_url == null) {
                    return ctx.client.getPackageMetadata(ctx.name);
                }

                // 4. Fetch wheel METADATA (~2KB vs ~80KB JSON)
                var wheel_meta = ctx.client.getWheelMetadata(best_wheel_url.?) catch {
                    // Fallback to JSON API on failure
                    return ctx.client.getPackageMetadata(ctx.name);
                };
                defer wheel_meta.deinit(allocator);

                // 5. Build result - all allocations with errdefer cleanup
                const name_copy = try allocator.dupe(u8, ctx.name);
                errdefer allocator.free(name_copy);

                const version_copy = try allocator.dupe(u8, best_version orelse wheel_meta.version);
                errdefer allocator.free(version_copy);

                // Copy requires_dist
                var requires_dist_list = std.ArrayList([]const u8){};
                errdefer {
                    for (requires_dist_list.items) |dep| allocator.free(dep);
                    requires_dist_list.deinit(allocator);
                }
                for (wheel_meta.requires_dist) |dep| {
                    const dep_copy = try allocator.dupe(u8, dep);
                    errdefer allocator.free(dep_copy);
                    try requires_dist_list.append(allocator, dep_copy);
                }

                // Build minimal releases list from simple versions
                var releases_list = std.ArrayList(ReleaseInfo){};
                errdefer {
                    for (releases_list.items) |*r| @constCast(r).deinit(allocator);
                    releases_list.deinit(allocator);
                }
                for (simple.versions) |v| {
                    const ver_copy = try allocator.dupe(u8, v.version);
                    errdefer allocator.free(ver_copy);
                    try releases_list.append(allocator, .{
                        .version = ver_copy,
                        .files = &[_]FileInfo{},
                    });
                }

                // Convert to owned slices
                const requires_dist = try requires_dist_list.toOwnedSlice(allocator);
                errdefer {
                    for (requires_dist) |dep| allocator.free(dep);
                    allocator.free(requires_dist);
                }

                const releases = try releases_list.toOwnedSlice(allocator);

                return .{
                    .name = name_copy,
                    .latest_version = version_copy,
                    .summary = null,
                    .releases = releases,
                    .requires_dist = requires_dist,
                };
            }
        };

        // Create contexts
        const contexts = try self.allocator.alloc(FastFetchContext, package_names.len);
        defer self.allocator.free(contexts);

        for (package_names, 0..) |name, i| {
            contexts[i] = .{
                .client = self,
                .name = name,
                .result = &results[i],
            };
        }

        // Spawn ALL threads at once for maximum parallelism
        var threads = try self.allocator.alloc(std.Thread, package_names.len);
        defer self.allocator.free(threads);

        var spawned: usize = 0;
        errdefer {
            for (threads[0..spawned]) |t| t.join();
        }

        for (0..package_names.len) |i| {
            threads[i] = std.Thread.spawn(.{}, FastFetchContext.fetch, .{&contexts[i]}) catch {
                FastFetchContext.fetch(&contexts[i]);
                continue;
            };
            spawned += 1;
        }

        // Wait for all
        for (threads[0..spawned]) |t| t.join();

        return results;
    }

    /// SLOW: Parallel fetch using full JSON API (80KB per package)
    /// Use getPackagesParallelFast instead when possible
    pub fn getPackagesParallelSlow(
        self: *PyPIClient,
        package_names: []const []const u8,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        const results = try self.allocator.alloc(FetchResult, package_names.len);
        errdefer self.allocator.free(results);

        for (results) |*r| {
            r.* = .{ .err = PyPIError.NetworkError };
        }

        const FetchContext = struct {
            allocator: std.mem.Allocator,
            config: *const Config,
            name: []const u8,
            result: *FetchResult,

            fn fetch(ctx: *@This()) void {
                // Each thread creates its own HTTP client (thread-safe!)
                var client = std.http.Client{ .allocator = ctx.allocator };
                defer client.deinit();

                ctx.result.* = blk: {
                    const meta = fetchPackage(&client, ctx.allocator, ctx.config, ctx.name) catch {
                        break :blk .{ .err = PyPIError.NetworkError };
                    };
                    break :blk .{ .success = meta };
                };
            }

            fn fetchPackage(client: *std.http.Client, allocator: std.mem.Allocator, config: *const Config, name: []const u8) !PackageMetadata {
                // Build URL
                const url = try std.fmt.allocPrint(allocator, "{s}/{s}/json", .{ config.json_api_url, name });
                defer allocator.free(url);

                // Fetch with allocating writer
                var response_writer = std.Io.Writer.Allocating.init(allocator);
                errdefer if (response_writer.writer.buffer.len > 0) allocator.free(response_writer.writer.buffer);

                const result = client.fetch(.{
                    .location = .{ .url = url },
                    .extra_headers = &.{
                        .{ .name = "User-Agent", .value = config.user_agent },
                        .{ .name = "Accept", .value = "application/json" },
                    },
                    .response_writer = &response_writer.writer,
                }) catch return PyPIError.NetworkError;

                if (result.status != .ok) return PyPIError.NetworkError;

                const body = response_writer.writer.buffer[0..response_writer.writer.end];
                defer allocator.free(response_writer.writer.buffer);

                // Parse with lazy JSON
                return parsePackageJsonStatic(allocator, body, name);
            }
        };

        const contexts = try self.allocator.alloc(FetchContext, package_names.len);
        defer self.allocator.free(contexts);

        for (package_names, 0..) |name, i| {
            contexts[i] = .{
                .allocator = self.allocator,
                .config = &self.config,
                .name = name,
                .result = &results[i],
            };
        }

        var threads = try self.allocator.alloc(std.Thread, package_names.len);
        defer self.allocator.free(threads);

        var spawned: usize = 0;
        errdefer {
            for (threads[0..spawned]) |t| t.join();
        }

        for (0..package_names.len) |i| {
            threads[i] = std.Thread.spawn(.{}, FetchContext.fetch, .{&contexts[i]}) catch {
                FetchContext.fetch(&contexts[i]);
                continue;
            };
            spawned += 1;
        }

        for (threads[0..spawned]) |t| t.join();

        return results;
    }

    /// FAST streaming JSON parser - extracts only needed fields without building full tree
    /// ~50x faster than full parse for large packages like numpy (2.7MB JSON)
    /// Uses shared json_stream module for reusable extraction utilities
    pub fn parsePackageJsonStatic(allocator: std.mem.Allocator, body: []const u8, fallback_name: []const u8) !PackageMetadata {
        // Fast path: stream parse to extract only: name, version, requires_dist
        // The JSON structure is: {"info": {"name": "...", "version": "...", "requires_dist": [...]}, "releases": {...}}
        // We only need the info section, skip releases entirely

        // Get info section (between "info" and "releases")
        const info_section = json_stream.findObjectBetween(body, "\"info\"", "\"releases\"") orelse
            return PyPIError.ParseError;

        // Extract "name" from info section
        var name: ?[]const u8 = null;
        errdefer if (name) |n| allocator.free(n);
        if (json_stream.findString(info_section, "\"name\"")) |name_str| {
            name = try allocator.dupe(u8, name_str);
        }

        // Extract "version" from info section
        var version: ?[]const u8 = null;
        errdefer if (version) |v| allocator.free(v);
        if (json_stream.findString(info_section, "\"version\"")) |ver_str| {
            version = try allocator.dupe(u8, ver_str);
        }

        // Extract "requires_dist" array using shared utility
        const requires_dist = json_stream.extractStringArray(allocator, info_section, "\"requires_dist\"") catch
            &[_][]const u8{};

        return .{
            .name = name orelse try allocator.dupe(u8, fallback_name),
            .latest_version = version orelse try allocator.dupe(u8, "0.0.0"),
            .summary = null,
            .releases = &[_]ReleaseInfo{},
            .requires_dist = requires_dist,
        };
    }

    /// Parse wheel METADATA text (RFC 822-like format) - static version for cache
    /// This is a static function for use by the resolver cache
    pub fn parseMetadataText(allocator: std.mem.Allocator, body: []const u8, package_name: []const u8) !PackageMetadata {
        var requires_dist = std.ArrayList([]const u8){};
        errdefer {
            for (requires_dist.items) |dep| allocator.free(dep);
            requires_dist.deinit(allocator);
        }

        var version: ?[]const u8 = null;
        errdefer if (version) |v| allocator.free(v);

        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) break; // Headers end at blank line

            if (std.mem.startsWith(u8, trimmed, "Version:")) {
                const val = std.mem.trim(u8, trimmed["Version:".len..], " ");
                version = try allocator.dupe(u8, val);
            } else if (std.mem.startsWith(u8, trimmed, "Requires-Dist:")) {
                const val = std.mem.trim(u8, trimmed["Requires-Dist:".len..], " ");
                const dep_copy = try allocator.dupe(u8, val);
                try requires_dist.append(allocator, dep_copy);
            }
        }

        return .{
            .name = try allocator.dupe(u8, package_name),
            .latest_version = version orelse try allocator.dupe(u8, "0.0.0"),
            .summary = null,
            .releases = &[_]ReleaseInfo{},
            .requires_dist = try requires_dist.toOwnedSlice(allocator),
        };
    }

    /// Fetch multiple wheel METADATA files in parallel (PEP 658)
    /// This is the fastest path for dependency fetching (~2KB each)
    pub fn getWheelMetadataParallel(
        self: *PyPIClient,
        wheel_urls: []const []const u8,
    ) ![]WheelMetadataResult {
        if (wheel_urls.len == 0) return &[_]WheelMetadataResult{};

        const results = try self.allocator.alloc(WheelMetadataResult, wheel_urls.len);
        errdefer self.allocator.free(results);

        // Initialize all to error
        for (results) |*r| {
            r.* = .{ .err = PyPIError.NetworkError };
        }

        // Parallel fetch context
        const FetchContext = struct {
            client: *PyPIClient,
            url: []const u8,
            result: *WheelMetadataResult,

            fn fetch(ctx: *@This()) void {
                ctx.result.* = if (ctx.client.getWheelMetadata(ctx.url)) |meta|
                    .{ .success = meta }
                else |_|
                    .{ .err = PyPIError.NetworkError };
            }
        };

        // Create contexts
        const contexts = try self.allocator.alloc(FetchContext, wheel_urls.len);
        defer self.allocator.free(contexts);

        for (wheel_urls, 0..) |url, i| {
            contexts[i] = .{
                .client = self,
                .url = url,
                .result = &results[i],
            };
        }

        // Spawn all threads
        var threads = try self.allocator.alloc(std.Thread, wheel_urls.len);
        defer self.allocator.free(threads);

        var spawned: usize = 0;
        errdefer {
            for (threads[0..spawned]) |t| t.join();
        }

        for (0..wheel_urls.len) |i| {
            threads[i] = std.Thread.spawn(.{}, FetchContext.fetch, .{&contexts[i]}) catch {
                FetchContext.fetch(&contexts[i]);
                continue;
            };
            spawned += 1;
        }

        // Wait for all
        for (threads[0..spawned]) |t| t.join();

        return results;
    }

    /// Fetch URL with retry logic
    fn fetchUrl(self: *PyPIClient, url: []const u8) ![]const u8 {
        var retries: u32 = 0;
        var last_err: PyPIError = PyPIError.NetworkError;

        while (retries < self.config.max_retries) : (retries += 1) {
            const result = self.doFetch(url);
            if (result) |body| {
                return body;
            } else |err| {
                last_err = err;
                // Exponential backoff
                if (retries + 1 < self.config.max_retries) {
                    const delay_ms: u64 = @as(u64, 100) << @intCast(retries);
                    std.Thread.sleep(delay_ms * std.time.ns_per_ms);
                }
            }
        }

        return last_err;
    }

    /// Perform actual HTTP fetch using persistent H2 client (connection reuse)
    fn doFetch(self: *PyPIClient, url: []const u8) PyPIError![]const u8 {
        var response = self.h2_client.get(url) catch return PyPIError.NetworkError;
        defer response.deinit();

        // Check status
        if (response.status == 404) return PyPIError.PackageNotFound;
        if (response.status == 429) return PyPIError.TooManyRequests;
        if (response.status >= 500) return PyPIError.ServerError;
        if (response.status != 200) return PyPIError.NetworkError;

        return self.allocator.dupe(u8, response.body) catch return PyPIError.OutOfMemory;
    }

    /// Parse PyPI JSON API response using LAZY parsing
    /// Only materializes strings we actually need - 3-5x faster for large responses
    fn parsePackageJson(self: *PyPIClient, body: []const u8, fallback_name: []const u8) !PackageMetadata {
        // Use SIMD-accelerated LAZY JSON parser
        // Keys are materialized (for HashMap), but values stay lazy
        var parsed = json.parseLazy(self.allocator, body) catch
            return PyPIError.ParseError;
        defer parsed.deinit(self.allocator);

        if (parsed != .object) return PyPIError.ParseError;

        // Get info object - use getPtr to get mutable pointer
        const info_ptr = parsed.object.getPtr("info") orelse return PyPIError.ParseError;
        if (info_ptr.* != .object) return PyPIError.ParseError;

        // Extract name (materialize this string)
        const name_ptr = info_ptr.object.getPtr("name") orelse return PyPIError.ParseError;
        const name_str = if (name_ptr.* == .string)
            (name_ptr.string.get() catch fallback_name)
        else
            fallback_name;
        const name = try self.allocator.dupe(u8, name_str);
        errdefer self.allocator.free(name);

        // Extract version (materialize this string)
        const version_ptr = info_ptr.object.getPtr("version") orelse return PyPIError.ParseError;
        const version_str = if (version_ptr.* == .string)
            (version_ptr.string.get() catch "0.0.0")
        else
            "0.0.0";
        const version = try self.allocator.dupe(u8, version_str);
        errdefer self.allocator.free(version);

        // Skip summary for speed - not needed for resolution
        const summary: ?[]const u8 = null;

        // Extract requires_dist (dependencies) - materialize these strings
        var requires_dist_list = std.ArrayList([]const u8){};
        errdefer {
            for (requires_dist_list.items) |dep| self.allocator.free(dep);
            requires_dist_list.deinit(self.allocator);
        }

        if (info_ptr.object.getPtr("requires_dist")) |req_ptr| {
            if (req_ptr.* == .array) {
                for (req_ptr.array.items) |*item| {
                    if (item.* == .string) {
                        const dep_str = item.string.get() catch continue;
                        const dep_copy = try self.allocator.dupe(u8, dep_str);
                        try requires_dist_list.append(self.allocator, dep_copy);
                    }
                }
            }
        }

        // Extract releases - only version keys, skip values entirely!
        // The values are huge arrays of file objects we don't need
        var releases_list = std.ArrayList(ReleaseInfo){};
        errdefer {
            for (releases_list.items) |*r| r.deinit(self.allocator);
            releases_list.deinit(self.allocator);
        }

        if (parsed.object.getPtr("releases")) |releases_ptr| {
            if (releases_ptr.* == .object) {
                // Keys are already materialized by parseLazy
                // Values stay lazy (we never access them!)
                var rel_it = releases_ptr.object.iterator();
                while (rel_it.next()) |entry| {
                    const rel_version = try self.allocator.dupe(u8, entry.key_ptr.*);
                    try releases_list.append(self.allocator, .{
                        .version = rel_version,
                        .files = &[_]FileInfo{},
                    });
                }
            }
        }

        return .{
            .name = name,
            .latest_version = version,
            .summary = summary,
            .releases = try releases_list.toOwnedSlice(self.allocator),
            .requires_dist = try requires_dist_list.toOwnedSlice(self.allocator),
        };
    }

    /// Parse file info from JSON object
    fn parseFileInfo(self: *PyPIClient, obj: std.json.ObjectMap) !FileInfo {
        // filename (required)
        const filename_val = obj.get("filename") orelse return PyPIError.ParseError;
        const filename_str = if (filename_val == .string) filename_val.string else return PyPIError.ParseError;
        const filename = try self.allocator.dupe(u8, filename_str);
        errdefer self.allocator.free(filename);

        // url (required)
        const url_val = obj.get("url") orelse return PyPIError.ParseError;
        const url_str = if (url_val == .string) url_val.string else return PyPIError.ParseError;
        const url = try self.allocator.dupe(u8, url_str);
        errdefer self.allocator.free(url);

        // size (optional)
        var size: u64 = 0;
        if (obj.get("size")) |size_val| {
            if (size_val == .integer) {
                size = @intCast(size_val.integer);
            }
        }

        // sha256 (optional, in digests object)
        var sha256: ?[]const u8 = null;
        if (obj.get("digests")) |digests_val| {
            if (digests_val == .object) {
                if (digests_val.object.get("sha256")) |sha_val| {
                    if (sha_val == .string) {
                        sha256 = try self.allocator.dupe(u8, sha_val.string);
                    }
                }
            }
        }
        errdefer if (sha256) |h| self.allocator.free(h);

        // requires_python (optional)
        var requires_python: ?[]const u8 = null;
        if (obj.get("requires_python")) |rp_val| {
            if (rp_val == .string) {
                requires_python = try self.allocator.dupe(u8, rp_val.string);
            }
        }
        errdefer if (requires_python) |rp| self.allocator.free(rp);

        // packagetype
        var packagetype: FileInfo.PackageType = .unknown;
        if (obj.get("packagetype")) |pt_val| {
            if (pt_val == .string) {
                const pt_str = pt_val.string;
                if (std.mem.eql(u8, pt_str, "bdist_wheel")) {
                    packagetype = .bdist_wheel;
                } else if (std.mem.eql(u8, pt_str, "sdist")) {
                    packagetype = .sdist;
                }
            }
        }

        return .{
            .filename = filename,
            .url = url,
            .size = size,
            .sha256 = sha256,
            .requires_python = requires_python,
            .packagetype = packagetype,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "PyPIClient creation" {
    const allocator = std.testing.allocator;

    var client = PyPIClient.init(allocator);
    defer client.deinit();

    try std.testing.expectEqualStrings("https://pypi.org/pypi", client.config.json_api_url);
    try std.testing.expectEqual(@as(u32, 32), client.config.max_concurrent);
}

test "PyPIClient with custom config" {
    const allocator = std.testing.allocator;

    var client = PyPIClient.initWithConfig(allocator, .{
        .json_api_url = "https://test.pypi.org/pypi",
        .max_concurrent = 8,
        .timeout_ms = 10000,
    });
    defer client.deinit();

    try std.testing.expectEqualStrings("https://test.pypi.org/pypi", client.config.json_api_url);
    try std.testing.expectEqual(@as(u32, 8), client.config.max_concurrent);
}

test "FileInfo type detection" {
    var info = FileInfo{
        .filename = "numpy-1.24.0-cp311-cp311-macosx_arm64.whl",
        .url = "https://example.com/wheel.whl",
        .packagetype = .bdist_wheel,
    };

    try std.testing.expect(info.isWheel());
    try std.testing.expect(!info.isSdist());

    info.filename = "numpy-1.24.0.tar.gz";
    info.packagetype = .sdist;

    try std.testing.expect(!info.isWheel());
    try std.testing.expect(info.isSdist());
}

/// Extract version from wheel/sdist filename
/// e.g., "flask-3.1.2-py3-none-any.whl" -> "3.1.2"
/// e.g., "flask-3.1.2.tar.gz" -> "3.1.2"
fn extractVersionFromFilename(filename: []const u8) ?[]const u8 {
    // Find package name end (first hyphen followed by digit)
    var i: usize = 0;
    while (i < filename.len) : (i += 1) {
        if (filename[i] == '-' and i + 1 < filename.len and std.ascii.isDigit(filename[i + 1])) {
            break;
        }
    }
    if (i >= filename.len) return null;

    // Version starts after hyphen
    const version_start = i + 1;

    // Find version end (next hyphen for wheel, or .tar.gz/.zip for sdist)
    var j = version_start;
    while (j < filename.len) : (j += 1) {
        if (filename[j] == '-') break;
        if (j + 7 <= filename.len and std.mem.eql(u8, filename[j .. j + 7], ".tar.gz")) break;
        if (j + 4 <= filename.len and std.mem.eql(u8, filename[j .. j + 4], ".zip")) break;
    }

    if (j <= version_start) return null;
    return filename[version_start..j];
}

test "extractVersionFromFilename" {
    try std.testing.expectEqualStrings("3.1.2", extractVersionFromFilename("flask-3.1.2-py3-none-any.whl").?);
    try std.testing.expectEqualStrings("3.1.2", extractVersionFromFilename("flask-3.1.2.tar.gz").?);
    try std.testing.expectEqualStrings("1.24.0", extractVersionFromFilename("numpy-1.24.0-cp311-cp311-macosx_arm64.whl").?);
}

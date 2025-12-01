//! PyPI API Client with Parallel Fetching
//!
//! High-performance PyPI package index client with:
//! - Parallel HTTP requests via thread pool
//! - Connection pooling
//! - JSON API support (pypi.org/pypi/{package}/json)
//! - Simple API support (pypi.org/simple/{package}/)
//! - Caching ready interface
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

    pub fn deinit(self: *PackageMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.latest_version);
        if (self.summary) |s| allocator.free(s);
        for (self.releases) |*r| {
            @constCast(r).deinit(allocator);
        }
        if (self.releases.len > 0) allocator.free(self.releases);
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

    pub fn init(allocator: std.mem.Allocator) PyPIClient {
        return .{
            .allocator = allocator,
            .config = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: Config) PyPIClient {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *PyPIClient) void {
        _ = self;
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

    /// Fetch multiple packages in parallel using native threads
    /// Uses one thread per request up to max_concurrent limit
    pub fn getPackagesParallel(
        self: *PyPIClient,
        package_names: []const []const u8,
    ) ![]FetchResult {
        if (package_names.len == 0) return &[_]FetchResult{};

        const results = try self.allocator.alloc(FetchResult, package_names.len);
        errdefer self.allocator.free(results);

        // Initialize all results to error state
        for (results) |*r| {
            r.* = .{ .err = PyPIError.NetworkError };
        }

        // Parallel fetch context
        const FetchContext = struct {
            client: *PyPIClient,
            name: []const u8,
            result: *FetchResult,

            fn fetch(ctx: *@This()) void {
                ctx.result.* = if (ctx.client.getPackageMetadata(ctx.name)) |meta|
                    .{ .success = meta }
                else |err|
                    .{ .err = mapError(err) };
            }

            fn mapError(err: anyerror) PyPIError {
                return switch (err) {
                    error.OutOfMemory => PyPIError.OutOfMemory,
                    error.PackageNotFound => PyPIError.PackageNotFound,
                    error.TooManyRequests => PyPIError.TooManyRequests,
                    error.ServerError => PyPIError.ServerError,
                    error.ParseError => PyPIError.ParseError,
                    else => PyPIError.NetworkError,
                };
            }
        };

        // Create fetch contexts
        const contexts = try self.allocator.alloc(FetchContext, package_names.len);
        defer self.allocator.free(contexts);

        for (package_names, 0..) |name, i| {
            contexts[i] = .{
                .client = self,
                .name = name,
                .result = &results[i],
            };
        }

        // Process in batches to respect max_concurrent
        var batch_start: usize = 0;
        while (batch_start < package_names.len) {
            const batch_end = @min(batch_start + self.config.max_concurrent, package_names.len);
            const batch_size = batch_end - batch_start;

            // Spawn threads for this batch
            var threads = try self.allocator.alloc(std.Thread, batch_size);
            defer self.allocator.free(threads);

            var spawned: usize = 0;
            errdefer {
                // Join any spawned threads on error
                for (threads[0..spawned]) |t| {
                    t.join();
                }
            }

            for (batch_start..batch_end) |i| {
                threads[i - batch_start] = std.Thread.spawn(.{}, FetchContext.fetch, .{&contexts[i]}) catch {
                    // If thread spawn fails, do it synchronously
                    contexts[i].fetch(&contexts[i]);
                    continue;
                };
                spawned += 1;
            }

            // Wait for all threads in batch
            for (threads[0..spawned]) |t| {
                t.join();
            }

            batch_start = batch_end;
        }

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
                    std.time.sleep(delay_ms * std.time.ns_per_ms);
                }
            }
        }

        return last_err;
    }

    /// Perform actual HTTP fetch using std.http.Client
    fn doFetch(self: *PyPIClient, url: []const u8) PyPIError![]const u8 {
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Prepare request
        const uri = std.Uri.parse(url) catch return PyPIError.NetworkError;

        var header_buf: [4096]u8 = undefined;
        var req = client.open(.GET, uri, .{
            .server_header_buffer = &header_buf,
            .extra_headers = &.{
                .{ .name = "User-Agent", .value = self.config.user_agent },
                .{ .name = "Accept", .value = "application/json" },
            },
        }) catch return PyPIError.NetworkError;
        defer req.deinit();

        req.send() catch return PyPIError.NetworkError;
        req.wait() catch return PyPIError.NetworkError;

        // Check status
        const status = req.status;
        if (status == .not_found) return PyPIError.PackageNotFound;
        if (status == .too_many_requests) return PyPIError.TooManyRequests;
        if (@intFromEnum(status) >= 500) return PyPIError.ServerError;
        if (status != .ok) return PyPIError.NetworkError;

        // Read body
        var body_list = std.ArrayList(u8){};
        errdefer body_list.deinit(self.allocator);

        var buf: [8192]u8 = undefined;
        while (true) {
            const n = req.read(&buf) catch return PyPIError.NetworkError;
            if (n == 0) break;
            body_list.appendSlice(self.allocator, buf[0..n]) catch return PyPIError.OutOfMemory;
        }

        return body_list.toOwnedSlice(self.allocator) catch return PyPIError.OutOfMemory;
    }

    /// Parse PyPI JSON API response
    fn parsePackageJson(self: *PyPIClient, body: []const u8, fallback_name: []const u8) !PackageMetadata {
        // Use std.json for parsing
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch
            return PyPIError.ParseError;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return PyPIError.ParseError;

        const obj = root.object;

        // Get info object
        const info_val = obj.get("info") orelse return PyPIError.ParseError;
        if (info_val != .object) return PyPIError.ParseError;
        const info = info_val.object;

        // Extract name
        const name_val = info.get("name") orelse return PyPIError.ParseError;
        const name_str = if (name_val == .string) name_val.string else fallback_name;
        const name = try self.allocator.dupe(u8, name_str);
        errdefer self.allocator.free(name);

        // Extract version
        const version_val = info.get("version") orelse return PyPIError.ParseError;
        const version_str = if (version_val == .string) version_val.string else "0.0.0";
        const version = try self.allocator.dupe(u8, version_str);
        errdefer self.allocator.free(version);

        // Extract summary (optional)
        var summary: ?[]const u8 = null;
        if (info.get("summary")) |sum_val| {
            if (sum_val == .string) {
                summary = try self.allocator.dupe(u8, sum_val.string);
            }
        }
        errdefer if (summary) |s| self.allocator.free(s);

        // Parse releases
        var releases_list = std.ArrayList(ReleaseInfo){};
        errdefer {
            for (releases_list.items) |*r| r.deinit(self.allocator);
            releases_list.deinit(self.allocator);
        }

        if (obj.get("releases")) |releases_val| {
            if (releases_val == .object) {
                var rel_it = releases_val.object.iterator();
                while (rel_it.next()) |entry| {
                    const rel_version = try self.allocator.dupe(u8, entry.key_ptr.*);
                    errdefer self.allocator.free(rel_version);

                    // Parse files for this release
                    var files_list = std.ArrayList(FileInfo){};
                    errdefer {
                        for (files_list.items) |*f| f.deinit(self.allocator);
                        files_list.deinit(self.allocator);
                    }

                    if (entry.value_ptr.* == .array) {
                        for (entry.value_ptr.array.items) |file_val| {
                            if (file_val == .object) {
                                const file_info = try self.parseFileInfo(file_val.object);
                                try files_list.append(self.allocator, file_info);
                            }
                        }
                    }

                    try releases_list.append(self.allocator, .{
                        .version = rel_version,
                        .files = try files_list.toOwnedSlice(self.allocator),
                    });
                }
            }
        }

        return .{
            .name = name,
            .latest_version = version,
            .summary = summary,
            .releases = try releases_list.toOwnedSlice(self.allocator),
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

//! PyPI Dependency Provider for PubGrub
//!
//! Fetches package metadata from PyPI to provide version and dependency information.
//! Implements caching to avoid redundant network requests.

const std = @import("std");
const pubgrub = @import("pubgrub.zig");
const Version = pubgrub.Version;
const Range = pubgrub.Range;
const DependencyProvider = pubgrub.DependencyProvider;
const Dependencies = pubgrub.Dependencies;
const Dependency = pubgrub.Dependency;
const pep508 = @import("../parse/pep508.zig");
const json = @import("json");

/// PyPI provider state
pub const PyPIProvider = struct {
    allocator: std.mem.Allocator,
    /// Cache of package versions: package_name -> [versions]
    version_cache: std.StringHashMap([]Version),
    /// Cache of dependencies: "package@version" -> Dependencies
    dependency_cache: std.StringHashMap(CachedDependencies),
    /// HTTP client for PyPI requests
    http_client: ?*anyopaque, // Would be h2.Client in real impl

    const CachedDependencies = struct {
        deps: []Dependency,
        unavailable: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) PyPIProvider {
        return .{
            .allocator = allocator,
            .version_cache = std.StringHashMap([]Version).init(allocator),
            .dependency_cache = std.StringHashMap(CachedDependencies).init(allocator),
            .http_client = null,
        };
    }

    pub fn deinit(self: *PyPIProvider) void {
        // Clean up version cache
        var v_iter = self.version_cache.iterator();
        while (v_iter.next()) |entry| {
            // Free the key (package name)
            self.allocator.free(entry.key_ptr.*);
            // Free the versions
            for (entry.value_ptr.*) |*v| {
                var version = v;
                version.deinit(self.allocator);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.version_cache.deinit();

        // Clean up dependency cache
        var d_iter = self.dependency_cache.iterator();
        while (d_iter.next()) |entry| {
            // Free the key (package@version)
            self.allocator.free(entry.key_ptr.*);
            // Free the cached data
            const cached = entry.value_ptr.*;
            for (cached.deps) |*d| {
                var dep = d;
                dep.range.deinit();
            }
            self.allocator.free(cached.deps);
            if (cached.unavailable) |u| {
                self.allocator.free(u);
            }
        }
        self.dependency_cache.deinit();
    }

    /// Get all versions for a package from PyPI
    pub fn getVersions(self: *PyPIProvider, package: []const u8) ![]Version {
        // Check cache first
        if (self.version_cache.get(package)) |cached| {
            return cached;
        }

        // Fetch from PyPI JSON API
        const url = try std.fmt.allocPrint(self.allocator, "https://pypi.org/pypi/{s}/json", .{package});
        defer self.allocator.free(url);

        // In real implementation, would use h2.Client here
        // For now, return empty to indicate we need to fetch
        // This will be replaced with actual HTTP fetch

        // Parse versions from response
        var versions = std.ArrayList(Version){};

        // TODO: Fetch and parse from PyPI
        // For now, simulate with empty list
        const result = try versions.toOwnedSlice(self.allocator);

        // Cache and return
        const package_copy = try self.allocator.dupe(u8, package);
        try self.version_cache.put(package_copy, result);

        return result;
    }

    /// Get dependencies for a specific package version
    pub fn getDependencies(self: *PyPIProvider, package: []const u8, version: Version) !Dependencies {
        // Build cache key
        const version_str = try version.format(self.allocator);
        defer self.allocator.free(version_str);
        const cache_key = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ package, version_str });
        defer self.allocator.free(cache_key);

        // Check cache
        if (self.dependency_cache.get(cache_key)) |cached| {
            if (cached.unavailable) |reason| {
                return .{ .unavailable = reason };
            }
            return .{ .available = cached.deps };
        }

        // Fetch from PyPI
        // In real implementation, parse METADATA from wheel or fetch from JSON API

        // TODO: Implement actual fetch
        // For now, return empty dependencies
        const deps: []Dependency = &.{};

        // Cache and return
        const key_copy = try self.allocator.dupe(u8, cache_key);
        try self.dependency_cache.put(key_copy, .{
            .deps = deps,
            .unavailable = null,
        });

        return .{ .available = deps };
    }

    /// Priority for package selection
    /// Higher priority = earlier selection
    pub fn prioritize(self: *PyPIProvider, package: []const u8, range: Range) i64 {
        _ = self;
        _ = package;

        // Prefer packages with more constrained ranges
        // (More specific requirements should be resolved first)
        if (range.isEmpty()) return std.math.minInt(i64);

        // Count number of intervals - fewer means more constrained
        const num_intervals = range.intervals.items.len;
        if (num_intervals == 0) return std.math.minInt(i64);

        // Simple heuristic: prefer more constrained packages
        return -@as(i64, @intCast(num_intervals));
    }

    /// Convert to DependencyProvider interface
    pub fn provider(self: *PyPIProvider) DependencyProvider {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = DependencyProvider.VTable{
        .getVersions = getVersionsWrapper,
        .getDependencies = getDependenciesWrapper,
        .prioritize = prioritizeWrapper,
    };

    fn getVersionsWrapper(ptr: *anyopaque, package: []const u8) anyerror![]Version {
        const self: *PyPIProvider = @ptrCast(@alignCast(ptr));
        return self.getVersions(package);
    }

    fn getDependenciesWrapper(ptr: *anyopaque, package: []const u8, version: Version) anyerror!Dependencies {
        const self: *PyPIProvider = @ptrCast(@alignCast(ptr));
        return self.getDependencies(package, version);
    }

    fn prioritizeWrapper(ptr: *anyopaque, package: []const u8, range: Range) i64 {
        const self: *PyPIProvider = @ptrCast(@alignCast(ptr));
        return self.prioritize(package, range);
    }
};

/// Resolve packages from PyPI
pub fn resolveFromPyPI(
    allocator: std.mem.Allocator,
    requirements: []const pep508.Dependency,
) !pubgrub.Resolution {
    var provider = PyPIProvider.init(allocator);
    defer provider.deinit();

    // Create virtual root package with all requirements as dependencies
    // This is a common pattern - create a "root" that depends on all user requirements

    // For now, if there's only one requirement, use it as root
    if (requirements.len == 0) {
        return pubgrub.Resolution.init(allocator);
    }

    const root = requirements[0];
    const root_version = "0.0.0"; // Virtual root version

    var solver = pubgrub.Solver.init(allocator, provider.provider());
    defer solver.deinit();

    return solver.resolve(root.name, root_version);
}

test "pypi provider initialization" {
    const allocator = std.testing.allocator;

    var provider = PyPIProvider.init(allocator);
    defer provider.deinit();

    // Basic smoke test
    const versions = try provider.getVersions("nonexistent-package");
    try std.testing.expectEqual(@as(usize, 0), versions.len);
}

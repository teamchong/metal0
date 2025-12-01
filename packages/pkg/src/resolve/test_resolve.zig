//! Resolver Test Harness
//!
//! Quick feedback loop for testing dependency resolution.
//! Run with: zig build resolve -- numpy pandas requests
//!
//! This fetches real metadata from PyPI and resolves dependencies.
//! Uses disk cache (~/.metal0/cache) for instant subsequent lookups.

const std = @import("std");
const pkg = @import("pkg");
const pep508 = pkg.pep508;
const pep440 = pkg.pep440;
const pypi = pkg.pypi;
const Resolver = pkg.Resolver;
const Cache = pkg.Cache;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: test_resolve <package1> [package2] ...\n", .{});
        std.debug.print("Example: test_resolve numpy pandas requests\n", .{});
        return;
    }

    // Parse package names into dependencies
    var deps = std.ArrayList(pep508.Dependency){};
    defer deps.deinit(allocator);

    for (args[1..]) |arg| {
        const dep = pep508.parseDependency(allocator, arg) catch |err| {
            std.debug.print("Failed to parse '{s}': {}\n", .{ arg, err });
            continue;
        };
        try deps.append(allocator, dep);
    }

    if (deps.items.len == 0) {
        std.debug.print("No valid packages to resolve\n", .{});
        return;
    }

    std.debug.print("\n=== Resolving {} package(s) ===\n\n", .{deps.items.len});

    // Initialize disk cache at ~/.metal0/cache
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.metal0/cache", .{home});
    defer allocator.free(cache_dir);

    var cache = Cache.init(allocator, .{
        .memory_size = 64 * 1024 * 1024, // 64MB memory cache
        .memory_ttl = 300, // 5 minutes in memory
        .disk_dir = cache_dir,
        .disk_ttl = 86400, // 24 hours on disk
    }) catch |err| {
        std.debug.print("Warning: Failed to init disk cache: {}, using memory only\n", .{err});
        return initWithoutDiskCache(allocator, deps.items);
    };
    defer cache.deinit();

    // Create PyPI client and resolver with cache
    var client = pypi.PyPIClient.init(allocator);
    defer client.deinit();

    var resolver = Resolver.init(allocator, &client, &cache);
    defer resolver.deinit();

    // Time the resolution
    const start = std.time.milliTimestamp();

    const result = resolver.resolve(deps.items) catch |err| {
        std.debug.print("Resolution failed: {}\n", .{err});

        const stats = resolver.stats();
        std.debug.print("\nStats:\n", .{});
        std.debug.print("  Iterations: {}\n", .{stats.iterations});
        std.debug.print("  Backtracks: {}\n", .{stats.backtrack_count});
        std.debug.print("  Network fetches: {}\n", .{stats.network_fetches});
        return;
    };
    defer {
        var res = result;
        res.deinit();
    }

    const elapsed = std.time.milliTimestamp() - start;

    // Print results
    std.debug.print("Resolved {} packages in {}ms:\n\n", .{ result.packages.len, elapsed });

    for (result.packages) |resolved_pkg| {
        var version_buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&version_buf);
        resolved_pkg.version.format(fbs.writer()) catch {};
        const version_str = fbs.getWritten();

        std.debug.print("  {s} == {s}\n", .{ resolved_pkg.name, version_str });
    }

    // Print stats
    const stats = resolver.stats();
    const cache_stats = cache.stats();
    std.debug.print("\nStats:\n", .{});
    std.debug.print("  Iterations: {}\n", .{stats.iterations});
    std.debug.print("  Backtracks: {}\n", .{stats.backtrack_count});
    std.debug.print("  Cache hits: {} (memory+disk)\n", .{cache_stats.hits});
    std.debug.print("  Cache misses: {}\n", .{cache_stats.misses});
    std.debug.print("  Network fetches: {}\n", .{stats.network_fetches});

    // Note: Root dependencies are now owned by the resolver after resolve() is called
    // The resolver's deinit() handles freeing pending deps including these
}

/// Fallback when disk cache fails to initialize
fn initWithoutDiskCache(allocator: std.mem.Allocator, deps: []const pep508.Dependency) !void {
    var client = pypi.PyPIClient.init(allocator);
    defer client.deinit();

    var resolver = Resolver.init(allocator, &client, null);
    defer resolver.deinit();

    const start = std.time.milliTimestamp();

    const result = resolver.resolve(deps) catch |err| {
        std.debug.print("Resolution failed: {}\n", .{err});
        return;
    };
    defer {
        var res = result;
        res.deinit();
    }

    const elapsed = std.time.milliTimestamp() - start;

    std.debug.print("Resolved {} packages in {}ms (no cache):\n\n", .{ result.packages.len, elapsed });

    for (result.packages) |resolved_pkg| {
        var version_buf: [64]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&version_buf);
        resolved_pkg.version.format(fbs.writer()) catch {};
        const version_str = fbs.getWritten();
        std.debug.print("  {s} == {s}\n", .{ resolved_pkg.name, version_str });
    }
}

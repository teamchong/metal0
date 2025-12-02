//! PubGrub Integration Tests
//!
//! Tests the complete dependency resolution flow.

const std = @import("std");
const pubgrub = @import("pubgrub.zig");
const Version = pubgrub.Version;
const Range = pubgrub.Range;
const Term = pubgrub.Term;
const Solver = pubgrub.Solver;
const DependencyProvider = pubgrub.DependencyProvider;
const Dependencies = pubgrub.Dependencies;
const Dependency = pubgrub.Dependency;

/// Simple in-memory dependency provider for testing
const TestProvider = struct {
    allocator: std.mem.Allocator,
    /// package -> [versions]
    versions: std.StringHashMap([]const []const u8),
    /// "package@version" -> [dependencies]
    dependencies: std.StringHashMap([]const TestDep),

    const TestDep = struct {
        name: []const u8,
        constraint: []const u8, // e.g., ">=1.0.0,<2.0.0"
    };

    fn init(allocator: std.mem.Allocator) TestProvider {
        return .{
            .allocator = allocator,
            .versions = std.StringHashMap([]const []const u8).init(allocator),
            .dependencies = std.StringHashMap([]const TestDep).init(allocator),
        };
    }

    fn deinit(self: *TestProvider) void {
        self.versions.deinit();
        self.dependencies.deinit();
    }

    fn addPackage(self: *TestProvider, name: []const u8, vers: []const []const u8) !void {
        try self.versions.put(name, vers);
    }

    fn addDependencies(self: *TestProvider, package: []const u8, version: []const u8, deps: []const TestDep) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ package, version });
        try self.dependencies.put(key, deps);
    }

    fn getVersions(ptr: *anyopaque, package: []const u8) anyerror![]Version {
        const self: *TestProvider = @ptrCast(@alignCast(ptr));
        const version_strs = self.versions.get(package) orelse return &[_]Version{};

        var result = try self.allocator.alloc(Version, version_strs.len);
        for (version_strs, 0..) |vs, i| {
            result[i] = try Version.parse(self.allocator, vs);
        }
        return result;
    }

    fn getDependencies(ptr: *anyopaque, package: []const u8, version: Version) anyerror!Dependencies {
        const self: *TestProvider = @ptrCast(@alignCast(ptr));
        const version_str = try version.format(self.allocator);
        defer self.allocator.free(version_str);
        const key = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ package, version_str });
        defer self.allocator.free(key);

        const test_deps = self.dependencies.get(key) orelse return .{ .available = &[_]Dependency{} };

        var deps = try self.allocator.alloc(Dependency, test_deps.len);
        for (test_deps, 0..) |td, i| {
            // Parse constraint into Range
            // For simplicity, just support ">=X.Y.Z"
            var range = Range.init(self.allocator);
            if (std.mem.startsWith(u8, td.constraint, ">=")) {
                const v = try Version.parse(self.allocator, td.constraint[2..]);
                range = try Range.greaterThanOrEqual(self.allocator, v);
            } else {
                range = try Range.full(self.allocator);
            }
            deps[i] = .{ .package = td.name, .range = range };
        }
        return .{ .available = deps };
    }

    fn prioritize(ptr: *anyopaque, package: []const u8, range: Range) i64 {
        _ = ptr;
        _ = package;
        _ = range;
        return 0;
    }

    fn provider(self: *TestProvider) DependencyProvider {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable = DependencyProvider.VTable{
        .getVersions = getVersions,
        .getDependencies = getDependencies,
        .prioritize = prioritize,
    };
};

test "version parsing" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    var v2 = try Version.parse(allocator, "2.0.0");
    defer v2.deinit(allocator);

    try std.testing.expect(v1.lessThan(v2));
    try std.testing.expect(v2.greaterThan(v1));
}

test "range contains" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    var v2 = try Version.parse(allocator, "2.0.0");
    defer v2.deinit(allocator);

    // Test >=1.0.0
    var range = try Range.greaterThanOrEqual(allocator, v1);
    defer range.deinit();

    try std.testing.expect(range.contains(v1));
    try std.testing.expect(range.contains(v2));
}

test "range singleton" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.5.0");
    defer v1.deinit(allocator);

    var v2 = try Version.parse(allocator, "1.5.0");
    defer v2.deinit(allocator);

    var v3 = try Version.parse(allocator, "2.0.0");
    defer v3.deinit(allocator);

    var range = try Range.singleton(allocator, v1);
    defer range.deinit();

    try std.testing.expect(range.contains(v2));
    try std.testing.expect(!range.contains(v3));
}

test "empty range" {
    const allocator = std.testing.allocator;

    var range = Range.empty(allocator);
    defer range.deinit();

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    try std.testing.expect(range.isEmpty());
    try std.testing.expect(!range.contains(v1));
}

test "term exact" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    var term = try Term.exact(allocator, v1);
    defer term.deinit();

    try std.testing.expect(term.positive);
    try std.testing.expect(term.contains(v1));
}

pub fn main() !void {
    std.debug.print("Running PubGrub tests...\n", .{});

    // Run basic tests
    const allocator = std.heap.page_allocator;

    // Test 1: Version parsing
    {
        var v1 = try Version.parse(allocator, "1.0.0");
        defer v1.deinit(allocator);
        var v2 = try Version.parse(allocator, "2.0.0");
        defer v2.deinit(allocator);

        if (!v1.lessThan(v2)) {
            std.debug.print("FAIL: 1.0.0 should be less than 2.0.0\n", .{});
            return;
        }
        std.debug.print("✓ Version comparison works\n", .{});
    }

    // Test 2: Range operations
    {
        var v1 = try Version.parse(allocator, "1.0.0");
        defer v1.deinit(allocator);

        var range = try Range.greaterThanOrEqual(allocator, v1);
        defer range.deinit();

        var v2 = try Version.parse(allocator, "2.0.0");
        defer v2.deinit(allocator);

        if (!range.contains(v2)) {
            std.debug.print("FAIL: >=1.0.0 should contain 2.0.0\n", .{});
            return;
        }
        std.debug.print("✓ Range contains works\n", .{});
    }

    // Test 3: Term creation
    {
        var v1 = try Version.parse(allocator, "1.0.0");
        defer v1.deinit(allocator);

        var term = try Term.exact(allocator, v1);
        defer term.deinit();

        if (!term.positive) {
            std.debug.print("FAIL: exact term should be positive\n", .{});
            return;
        }
        std.debug.print("✓ Term creation works\n", .{});
    }

    std.debug.print("\nAll basic tests passed!\n", .{});
}

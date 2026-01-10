//! importlib.metadata - Access metadata for installed packages
//! Reference: cpython/Lib/importlib/metadata/__init__.py
//!
//! CPython __all__:
//!   ['Distribution', 'DistributionFinder', 'PackageMetadata',
//!    'PackageNotFoundError', 'distribution', 'distributions',
//!    'entry_points', 'files', 'metadata', 'packages_distributions',
//!    'requires', 'version']

const std = @import("std");
const importlib = @import("../importlib.zig");

// ============================================================================
// Error Types
// ============================================================================

/// Error when a package is not found
pub const PackageNotFoundError = error{
    PackageNotFound,
};

// ============================================================================
// Types
// ============================================================================

/// Package metadata - key-value store for package info
/// CPython: class PackageMetadata(Protocol)
pub const PackageMetadata = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    pub fn get(self: *const Self, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn getAll(self: *const Self, key: []const u8) ?[]const u8 {
        return self.get(key);
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        try self.data.put(key, value);
    }
};

/// Entry point definition
/// CPython: class EntryPoint
pub const EntryPoint = struct {
    name: []const u8,
    value: []const u8,
    group: []const u8,

    pub fn init(name: []const u8, value: []const u8, group: []const u8) EntryPoint {
        return .{ .name = name, .value = value, .group = group };
    }

    /// Parse module from value (e.g., "package.module:attr")
    pub fn getModule(self: *const EntryPoint) []const u8 {
        const colon_pos = std.mem.indexOf(u8, self.value, ":") orelse self.value.len;
        return self.value[0..colon_pos];
    }

    /// Parse attr from value
    pub fn getAttr(self: *const EntryPoint) ?[]const u8 {
        const colon_pos = std.mem.indexOf(u8, self.value, ":") orelse return null;
        const bracket_pos = std.mem.indexOf(u8, self.value[colon_pos + 1 ..], "[") orelse self.value.len - colon_pos - 1;
        return self.value[colon_pos + 1 .. colon_pos + 1 + bracket_pos];
    }
};

/// Collection of entry points
pub const EntryPoints = struct {
    items: std.ArrayList(EntryPoint),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EntryPoints {
        return .{
            .items = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EntryPoints) void {
        self.items.deinit(self.allocator);
    }

    pub fn select(self: *const EntryPoints, allocator: std.mem.Allocator, group: ?[]const u8, name: ?[]const u8) !EntryPoints {
        var result = EntryPoints.init(allocator);
        for (self.items.items) |ep| {
            const matches_group = group == null or std.mem.eql(u8, ep.group, group.?);
            const matches_name = name == null or std.mem.eql(u8, ep.name, name.?);
            if (matches_group and matches_name) {
                try result.items.append(allocator, ep);
            }
        }
        return result;
    }
};

/// Package path - reference to a file in a package
/// CPython: class PackagePath
pub const PackagePath = struct {
    path: []const u8,
    hash: ?[]const u8 = null,
    size: ?usize = null,

    pub fn init(path: []const u8) PackagePath {
        return .{ .path = path };
    }

    pub fn readText(self: *const PackagePath, allocator: std.mem.Allocator) ![]u8 {
        const file = try std.fs.cwd().openFile(self.path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, std.math.maxInt(usize));
    }

    pub fn readBinary(self: *const PackagePath, allocator: std.mem.Allocator) ![]u8 {
        return self.readText(allocator);
    }
};

/// Abstract distribution - represents an installed package
/// CPython: class Distribution
pub const Distribution = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _name: []const u8,
    _path: ?[]const u8 = null,
    _metadata: ?PackageMetadata = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            ._name = name,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._metadata) |*m| {
            m.deinit();
        }
    }

    /// Get the Distribution for a package name
    pub fn fromName(allocator: std.mem.Allocator, name: []const u8) !Self {
        // In AOT, packages are compiled in; check if it exists
        // This is a stub - real impl would search sys.path
        if (name.len == 0) return error.PackageNotFound;
        return Self.init(allocator, name);
    }

    /// Get name of the distribution
    pub fn name(self: *const Self) []const u8 {
        return self._name;
    }

    /// Get version from metadata
    pub fn version(self: *Self) ![]const u8 {
        const meta = try self.metadata();
        return meta.get("Version") orelse "0.0.0";
    }

    /// Get metadata for this distribution
    pub fn metadata(self: *Self) !*PackageMetadata {
        if (self._metadata == null) {
            self._metadata = PackageMetadata.init(self.allocator);
            // Stub: would read METADATA file
            try self._metadata.?.put("Name", self._name);
            try self._metadata.?.put("Version", "0.0.0");
        }
        return &self._metadata.?;
    }

    /// Get entry points for this distribution
    pub fn entryPoints(self: *const Self) EntryPoints {
        _ = self;
        return EntryPoints.init(self.allocator);
    }

    /// Get files for this distribution
    pub fn files(self: *const Self) ?std.ArrayList(PackagePath) {
        _ = self;
        return null;
    }

    /// Get requires for this distribution
    pub fn requires(self: *Self) !?std.ArrayList([]const u8) {
        const meta = try self.metadata();
        const req = meta.get("Requires-Dist");
        if (req == null) return null;

        var result = std.ArrayList([]const u8){};
        try result.append(self.allocator, req.?);
        return result;
    }

    /// Read a text file from the distribution
    pub fn readText(self: *const Self, filename: []const u8) ?[]const u8 {
        _ = self;
        _ = filename;
        return null;
    }

    /// Locate a file in the distribution
    pub fn locateFile(self: *const Self, path: []const u8) []const u8 {
        _ = self;
        return path;
    }
};

/// Finder for distributions
/// CPython: class DistributionFinder(MetaPathFinder)
pub const DistributionFinder = struct {
    /// Context for distribution discovery
    pub const Context = struct {
        name: ?[]const u8 = null,
        path: ?[]const []const u8 = null,
    };

    /// Find distributions matching the context
    pub fn findDistributions(allocator: std.mem.Allocator, context: Context) !std.ArrayList(Distribution) {
        var result = std.ArrayList(Distribution){};
        if (context.name) |name| {
            const dist = try Distribution.fromName(allocator, name);
            try result.append(allocator, dist);
        }
        return result;
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Get the Distribution for a package name
/// CPython: def distribution(distribution_name: str) -> Distribution
pub fn distribution(allocator: std.mem.Allocator, distribution_name: []const u8) !Distribution {
    return Distribution.fromName(allocator, distribution_name);
}

/// Get all distributions in the environment
/// CPython: def distributions(**kwargs) -> Iterable[Distribution]
pub fn distributions(allocator: std.mem.Allocator) !std.ArrayList(Distribution) {
    // Stub: would enumerate installed packages
    return std.ArrayList(Distribution){}.init(allocator);
}

/// Get metadata for a package
/// CPython: def metadata(distribution_name: str) -> PackageMetadata
pub fn getMetadata(allocator: std.mem.Allocator, distribution_name: []const u8) !PackageMetadata {
    var dist = try Distribution.fromName(allocator, distribution_name);
    defer dist.deinit();
    return (try dist.metadata()).*;
}

/// Get version for a package
/// CPython: def version(distribution_name: str) -> str
pub fn version(allocator: std.mem.Allocator, distribution_name: []const u8) ![]const u8 {
    var dist = try Distribution.fromName(allocator, distribution_name);
    defer dist.deinit();
    return try dist.version();
}

/// Get entry points for all packages
/// CPython: def entry_points(**params) -> EntryPoints
pub fn entryPoints(allocator: std.mem.Allocator) !EntryPoints {
    return EntryPoints.init(allocator);
}

/// Get files for a package
/// CPython: def files(distribution_name: str) -> Optional[List[PackagePath]]
pub fn getFiles(allocator: std.mem.Allocator, distribution_name: []const u8) !?std.ArrayList(PackagePath) {
    var dist = try Distribution.fromName(allocator, distribution_name);
    defer dist.deinit();
    return dist.files();
}

/// Get requires for a package
/// CPython: def requires(distribution_name: str) -> Optional[List[str]]
pub fn getRequires(allocator: std.mem.Allocator, distribution_name: []const u8) !?std.ArrayList([]const u8) {
    var dist = try Distribution.fromName(allocator, distribution_name);
    return try dist.requires();
}

/// Get mapping of top-level packages to distributions
/// CPython: def packages_distributions() -> Mapping[str, List[str]]
pub fn packagesDistributions(allocator: std.mem.Allocator) !std.StringHashMap(std.ArrayList([]const u8)) {
    return std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "PackageMetadata" {
    const allocator = std.testing.allocator;
    var meta = PackageMetadata.init(allocator);
    defer meta.deinit();

    try meta.put("Name", "testpkg");
    try std.testing.expectEqualStrings("testpkg", meta.get("Name").?);
}

test "EntryPoint parsing" {
    const ep = EntryPoint.init("console_script", "mypackage.cli:main", "console_scripts");
    try std.testing.expectEqualStrings("mypackage.cli", ep.getModule());
    try std.testing.expectEqualStrings("main", ep.getAttr().?);
}

test "Distribution init" {
    const allocator = std.testing.allocator;
    var dist = Distribution.init(allocator, "testpkg");
    defer dist.deinit();

    try std.testing.expectEqualStrings("testpkg", dist.name());
}

test "PackagePath" {
    const pp = PackagePath.init("README.md");
    try std.testing.expectEqualStrings("README.md", pp.path);
}

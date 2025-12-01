//! METADATA Parser (RFC 822 / Email Headers)
//!
//! Parses package metadata from dist-info/METADATA files.
//!
//! ## Format (RFC 822 style)
//! ```
//! Metadata-Version: 2.1
//! Name: numpy
//! Version: 1.24.0
//! Requires-Python: >=3.8
//! Requires-Dist: pytest; extra == "test"
//! ```
//!
//! Reference: https://packaging.python.org/en/latest/specifications/core-metadata/

const std = @import("std");
const pep508 = @import("pep508.zig");
const pep440 = @import("pep440.zig");

/// Parsed package metadata
pub const PackageMetadata = struct {
    // Required fields
    metadata_version: []const u8 = "2.1",
    name: []const u8,
    version: []const u8,

    // Optional fields
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    description_content_type: ?[]const u8 = null,
    keywords: []const []const u8 = &[_][]const u8{},
    home_page: ?[]const u8 = null,
    download_url: ?[]const u8 = null,
    author: ?[]const u8 = null,
    author_email: ?[]const u8 = null,
    maintainer: ?[]const u8 = null,
    maintainer_email: ?[]const u8 = null,
    license: ?[]const u8 = null,
    classifiers: []const []const u8 = &[_][]const u8{},
    platform: []const []const u8 = &[_][]const u8{},
    requires_python: ?[]const u8 = null,
    requires_dist: []const []const u8 = &[_][]const u8{},
    requires_external: []const []const u8 = &[_][]const u8{},
    provides_extra: []const []const u8 = &[_][]const u8{},
    project_url: []const ProjectUrl = &[_]ProjectUrl{},

    pub const ProjectUrl = struct {
        label: []const u8,
        url: []const u8,
    };

    /// Parse requires_python as a version spec
    pub fn pythonVersionSpec(self: PackageMetadata, allocator: std.mem.Allocator) !?pep440.VersionSpec {
        if (self.requires_python) |spec_str| {
            return try pep440.parseSpec(allocator, spec_str);
        }
        return null;
    }

    /// Parse all requires_dist as dependencies
    pub fn dependencies(self: PackageMetadata, allocator: std.mem.Allocator) ![]pep508.Dependency {
        var deps = std.ArrayList(pep508.Dependency).init(allocator);
        errdefer {
            for (deps.items) |*d| pep508.freeDependency(allocator, d);
            deps.deinit();
        }

        for (self.requires_dist) |dep_str| {
            const dep = try pep508.parseDependency(allocator, dep_str);
            try deps.append(dep);
        }

        return deps.toOwnedSlice();
    }

    /// Get dependencies for a specific extra
    pub fn dependenciesForExtra(self: PackageMetadata, allocator: std.mem.Allocator, extra: []const u8) ![]pep508.Dependency {
        var deps = std.ArrayList(pep508.Dependency).init(allocator);
        errdefer {
            for (deps.items) |*d| pep508.freeDependency(allocator, d);
            deps.deinit();
        }

        for (self.requires_dist) |dep_str| {
            // Check if this dependency is for our extra
            if (std.mem.indexOf(u8, dep_str, "extra ==") != null or
                std.mem.indexOf(u8, dep_str, "extra==") != null)
            {
                // Check if it matches our extra
                var buf: [256]u8 = undefined;
                const patterns = [_][]const u8{
                    std.fmt.bufPrint(&buf, "extra == \"{s}\"", .{extra}) catch continue,
                    std.fmt.bufPrint(&buf, "extra==\"{s}\"", .{extra}) catch continue,
                    std.fmt.bufPrint(&buf, "extra == '{s}'", .{extra}) catch continue,
                    std.fmt.bufPrint(&buf, "extra=='{s}'", .{extra}) catch continue,
                };

                var matches = false;
                for (patterns) |pattern| {
                    if (std.mem.indexOf(u8, dep_str, pattern) != null) {
                        matches = true;
                        break;
                    }
                }

                if (!matches) continue;
            } else {
                // No extra marker, it's a core dependency - skip when looking for extras
                continue;
            }

            const dep = try pep508.parseDependency(allocator, dep_str);
            try deps.append(dep);
        }

        return deps.toOwnedSlice();
    }

    /// Get core dependencies (no extra markers)
    pub fn coreDependencies(self: PackageMetadata, allocator: std.mem.Allocator) ![]pep508.Dependency {
        var deps = std.ArrayList(pep508.Dependency).init(allocator);
        errdefer {
            for (deps.items) |*d| pep508.freeDependency(allocator, d);
            deps.deinit();
        }

        for (self.requires_dist) |dep_str| {
            // Skip dependencies with extra markers
            if (std.mem.indexOf(u8, dep_str, "extra ==") != null or
                std.mem.indexOf(u8, dep_str, "extra==") != null)
            {
                continue;
            }

            const dep = try pep508.parseDependency(allocator, dep_str);
            try deps.append(dep);
        }

        return deps.toOwnedSlice();
    }
};

pub const ParseError = error{
    InvalidFormat,
    MissingRequiredField,
    OutOfMemory,
};

/// Parse METADATA file content
pub fn parse(allocator: std.mem.Allocator, content: []const u8) ParseError!PackageMetadata {
    var metadata = PackageMetadata{ .name = "", .version = "" };

    var keywords = std.ArrayList([]const u8){};
    errdefer keywords.deinit(allocator);
    var classifiers = std.ArrayList([]const u8){};
    errdefer classifiers.deinit(allocator);
    var platforms = std.ArrayList([]const u8){};
    errdefer platforms.deinit(allocator);
    var requires_dist = std.ArrayList([]const u8){};
    errdefer requires_dist.deinit(allocator);
    var requires_external = std.ArrayList([]const u8){};
    errdefer requires_external.deinit(allocator);
    var provides_extra = std.ArrayList([]const u8){};
    errdefer provides_extra.deinit(allocator);
    var project_urls = std.ArrayList(PackageMetadata.ProjectUrl){};
    errdefer project_urls.deinit(allocator);

    // Split into headers and body (separated by blank line)
    var in_body = false;
    var body_start: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;

    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        line_num += 1;

        if (!in_body) {
            // Empty line marks start of body
            if (line.len == 0) {
                in_body = true;
                body_start = lines.index orelse content.len;
                continue;
            }

            // Parse header line
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const key = line[0..colon_pos];
                const value = line[colon_pos + 2 ..];

                if (std.ascii.eqlIgnoreCase(key, "Metadata-Version")) {
                    metadata.metadata_version = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Name")) {
                    metadata.name = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Version")) {
                    metadata.version = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Summary")) {
                    metadata.summary = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Home-page") or std.ascii.eqlIgnoreCase(key, "Home-Page")) {
                    metadata.home_page = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Download-URL")) {
                    metadata.download_url = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Author")) {
                    metadata.author = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Author-email") or std.ascii.eqlIgnoreCase(key, "Author-Email")) {
                    metadata.author_email = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Maintainer")) {
                    metadata.maintainer = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Maintainer-email") or std.ascii.eqlIgnoreCase(key, "Maintainer-Email")) {
                    metadata.maintainer_email = value;
                } else if (std.ascii.eqlIgnoreCase(key, "License")) {
                    metadata.license = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Keywords")) {
                    // Keywords are comma-separated
                    var kw_iter = std.mem.splitScalar(u8, value, ',');
                    while (kw_iter.next()) |kw| {
                        const trimmed = std.mem.trim(u8, kw, " \t");
                        if (trimmed.len > 0) {
                            try keywords.append(allocator, trimmed);
                        }
                    }
                } else if (std.ascii.eqlIgnoreCase(key, "Classifier")) {
                    try classifiers.append(allocator, value);
                } else if (std.ascii.eqlIgnoreCase(key, "Platform")) {
                    try platforms.append(allocator, value);
                } else if (std.ascii.eqlIgnoreCase(key, "Requires-Python")) {
                    metadata.requires_python = value;
                } else if (std.ascii.eqlIgnoreCase(key, "Requires-Dist")) {
                    try requires_dist.append(allocator, value);
                } else if (std.ascii.eqlIgnoreCase(key, "Requires-External")) {
                    try requires_external.append(allocator, value);
                } else if (std.ascii.eqlIgnoreCase(key, "Provides-Extra")) {
                    try provides_extra.append(allocator, value);
                } else if (std.ascii.eqlIgnoreCase(key, "Project-URL")) {
                    // Format: "Label, URL"
                    if (std.mem.indexOf(u8, value, ", ")) |comma_pos| {
                        try project_urls.append(allocator, .{
                            .label = value[0..comma_pos],
                            .url = value[comma_pos + 2 ..],
                        });
                    }
                } else if (std.ascii.eqlIgnoreCase(key, "Description-Content-Type")) {
                    metadata.description_content_type = value;
                }
            }
        }
    }

    // Body is the description
    if (in_body and body_start < content.len) {
        metadata.description = std.mem.trim(u8, content[body_start..], " \t\n\r");
        if (metadata.description.?.len == 0) {
            metadata.description = null;
        }
    }

    // Convert ArrayLists to slices
    metadata.keywords = try keywords.toOwnedSlice(allocator);
    metadata.classifiers = try classifiers.toOwnedSlice(allocator);
    metadata.platform = try platforms.toOwnedSlice(allocator);
    metadata.requires_dist = try requires_dist.toOwnedSlice(allocator);
    metadata.requires_external = try requires_external.toOwnedSlice(allocator);
    metadata.provides_extra = try provides_extra.toOwnedSlice(allocator);
    metadata.project_url = try project_urls.toOwnedSlice(allocator);

    // Validate required fields
    if (metadata.name.len == 0) return ParseError.MissingRequiredField;
    if (metadata.version.len == 0) return ParseError.MissingRequiredField;

    return metadata;
}

/// Free parsed metadata
pub fn free(allocator: std.mem.Allocator, m: *PackageMetadata) void {
    if (m.keywords.len > 0) allocator.free(m.keywords);
    if (m.classifiers.len > 0) allocator.free(m.classifiers);
    if (m.platform.len > 0) allocator.free(m.platform);
    if (m.requires_dist.len > 0) allocator.free(m.requires_dist);
    if (m.requires_external.len > 0) allocator.free(m.requires_external);
    if (m.provides_extra.len > 0) allocator.free(m.provides_extra);
    if (m.project_url.len > 0) allocator.free(m.project_url);
}

/// Parse METADATA from a file path
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !PackageMetadata {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    return parse(allocator, content);
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple metadata" {
    const allocator = std.testing.allocator;

    const content =
        \\Metadata-Version: 2.1
        \\Name: numpy
        \\Version: 1.24.0
        \\Summary: Fundamental package for scientific computing
    ;

    var m = try parse(allocator, content);
    defer free(allocator, &m);

    try std.testing.expectEqualStrings("2.1", m.metadata_version);
    try std.testing.expectEqualStrings("numpy", m.name);
    try std.testing.expectEqualStrings("1.24.0", m.version);
    try std.testing.expectEqualStrings("Fundamental package for scientific computing", m.summary.?);
}

test "parse metadata with dependencies" {
    const allocator = std.testing.allocator;

    const content =
        \\Metadata-Version: 2.1
        \\Name: mypackage
        \\Version: 1.0.0
        \\Requires-Python: >=3.8
        \\Requires-Dist: numpy>=1.20
        \\Requires-Dist: pandas
        \\Requires-Dist: pytest; extra == "test"
        \\Provides-Extra: test
    ;

    var m = try parse(allocator, content);
    defer free(allocator, &m);

    try std.testing.expectEqualStrings(">=3.8", m.requires_python.?);
    try std.testing.expectEqual(@as(usize, 3), m.requires_dist.len);
    try std.testing.expectEqual(@as(usize, 1), m.provides_extra.len);
    try std.testing.expectEqualStrings("test", m.provides_extra[0]);
}

test "parse metadata with description body" {
    const allocator = std.testing.allocator;

    const content =
        \\Metadata-Version: 2.1
        \\Name: mypackage
        \\Version: 1.0.0
        \\
        \\This is the long description.
        \\It can span multiple lines.
    ;

    var m = try parse(allocator, content);
    defer free(allocator, &m);

    try std.testing.expect(m.description != null);
    try std.testing.expect(std.mem.indexOf(u8, m.description.?, "long description") != null);
}

test "parse metadata with classifiers" {
    const allocator = std.testing.allocator;

    const content =
        \\Metadata-Version: 2.1
        \\Name: mypackage
        \\Version: 1.0.0
        \\Classifier: Development Status :: 5 - Production/Stable
        \\Classifier: License :: OSI Approved :: MIT License
        \\Classifier: Programming Language :: Python :: 3
    ;

    var m = try parse(allocator, content);
    defer free(allocator, &m);

    try std.testing.expectEqual(@as(usize, 3), m.classifiers.len);
    try std.testing.expectEqualStrings("Development Status :: 5 - Production/Stable", m.classifiers[0]);
}

test "parse metadata with project URLs" {
    const allocator = std.testing.allocator;

    const content =
        \\Metadata-Version: 2.1
        \\Name: mypackage
        \\Version: 1.0.0
        \\Project-URL: Homepage, https://example.com
        \\Project-URL: Documentation, https://docs.example.com
    ;

    var m = try parse(allocator, content);
    defer free(allocator, &m);

    try std.testing.expectEqual(@as(usize, 2), m.project_url.len);
    try std.testing.expectEqualStrings("Homepage", m.project_url[0].label);
    try std.testing.expectEqualStrings("https://example.com", m.project_url[0].url);
}

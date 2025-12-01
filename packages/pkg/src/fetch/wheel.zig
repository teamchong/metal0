//! Wheel File Selection and Platform Compatibility
//!
//! Selects the best wheel for the current platform based on:
//! - Python version compatibility
//! - Platform tags (OS, architecture)
//! - ABI compatibility
//!
//! ## Wheel Filename Format (PEP 427)
//! ```
//! {distribution}-{version}(-{build})?-{python}-{abi}-{platform}.whl
//! ```
//!
//! Examples:
//! - numpy-1.24.0-cp311-cp311-macosx_11_0_arm64.whl
//! - requests-2.28.0-py3-none-any.whl

const std = @import("std");
const pypi = @import("pypi.zig");

/// Parsed wheel filename components
pub const WheelInfo = struct {
    distribution: []const u8,
    version: []const u8,
    build: ?[]const u8 = null,
    python_tags: []const []const u8,
    abi_tags: []const []const u8,
    platform_tags: []const []const u8,

    /// Original filename
    filename: []const u8,
    /// URL to download
    url: []const u8,
    /// File size
    size: u64,
    /// SHA256 hash
    sha256: ?[]const u8,

    pub fn deinit(self: *WheelInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.distribution);
        allocator.free(self.version);
        if (self.build) |b| allocator.free(b);
        for (self.python_tags) |t| allocator.free(t);
        allocator.free(self.python_tags);
        for (self.abi_tags) |t| allocator.free(t);
        allocator.free(self.abi_tags);
        for (self.platform_tags) |t| allocator.free(t);
        allocator.free(self.platform_tags);
        allocator.free(self.filename);
        allocator.free(self.url);
        if (self.sha256) |h| allocator.free(h);
    }

    /// Check if wheel is universal (py3-none-any)
    pub fn isUniversal(self: WheelInfo) bool {
        for (self.platform_tags) |tag| {
            if (std.mem.eql(u8, tag, "any")) {
                for (self.abi_tags) |abi| {
                    if (std.mem.eql(u8, abi, "none")) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// Check if wheel matches Python version (e.g., "3.11")
    pub fn matchesPythonVersion(self: WheelInfo, major: u8, minor: u8) bool {
        for (self.python_tags) |tag| {
            // py3 matches any Python 3.x
            if (std.mem.eql(u8, tag, "py3")) return true;

            // cp311 matches Python 3.11
            if (tag.len >= 4 and std.mem.startsWith(u8, tag, "cp")) {
                const ver_str = tag[2..];
                if (ver_str.len >= 2) {
                    const tag_major = std.fmt.parseInt(u8, ver_str[0..1], 10) catch continue;
                    const tag_minor = std.fmt.parseInt(u8, ver_str[1..], 10) catch continue;
                    if (tag_major == major and tag_minor == minor) return true;
                }
            }

            // py311 matches Python 3.11
            if (tag.len >= 4 and std.mem.startsWith(u8, tag, "py")) {
                const ver_str = tag[2..];
                if (ver_str.len >= 2) {
                    const tag_major = std.fmt.parseInt(u8, ver_str[0..1], 10) catch continue;
                    const tag_minor = std.fmt.parseInt(u8, ver_str[1..], 10) catch continue;
                    if (tag_major == major and tag_minor == minor) return true;
                }
            }
        }
        return false;
    }
};

/// Platform specification
pub const Platform = struct {
    os: OS,
    arch: Arch,
    python_major: u8 = 3,
    python_minor: u8 = 11,
    glibc_version: ?struct { major: u8, minor: u8 } = null,
    macos_version: ?struct { major: u8, minor: u8 } = null,

    pub const OS = enum {
        linux,
        macos,
        windows,
        unknown,
    };

    pub const Arch = enum {
        x86_64,
        aarch64,
        arm,
        i686,
        unknown,
    };

    /// Detect current platform
    pub fn detect() Platform {
        const target = @import("builtin").target;

        const os: OS = switch (target.os.tag) {
            .linux => .linux,
            .macos => .macos,
            .windows => .windows,
            else => .unknown,
        };

        const arch: Arch = switch (target.cpu.arch) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
            .arm => .arm,
            .x86 => .i686,
            else => .unknown,
        };

        return .{
            .os = os,
            .arch = arch,
            // TODO: Detect actual Python version and glibc version
        };
    }

    /// Get platform tag strings for this platform
    pub fn getPlatformTags(self: Platform, allocator: std.mem.Allocator) ![][]const u8 {
        var tags = std.ArrayList([]const u8){};
        errdefer {
            for (tags.items) |t| allocator.free(t);
            tags.deinit(allocator);
        }

        // Add "any" tag (universal wheels)
        try tags.append(allocator, try allocator.dupe(u8, "any"));

        switch (self.os) {
            .linux => {
                switch (self.arch) {
                    .x86_64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "linux_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux1_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux2010_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux2014_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux_2_17_x86_64"));
                    },
                    .aarch64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "linux_aarch64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux2014_aarch64"));
                        try tags.append(allocator, try allocator.dupe(u8, "manylinux_2_17_aarch64"));
                    },
                    else => {},
                }
            },
            .macos => {
                switch (self.arch) {
                    .x86_64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_9_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_10_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_11_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_12_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_13_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_14_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_15_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_11_0_x86_64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_10_9_universal2"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_11_0_universal2"));
                    },
                    .aarch64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_11_0_arm64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_12_0_arm64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_13_0_arm64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_14_0_arm64"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_11_0_universal2"));
                        try tags.append(allocator, try allocator.dupe(u8, "macosx_12_0_universal2"));
                    },
                    else => {},
                }
            },
            .windows => {
                switch (self.arch) {
                    .x86_64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "win_amd64"));
                    },
                    .i686 => {
                        try tags.append(allocator, try allocator.dupe(u8, "win32"));
                    },
                    .aarch64 => {
                        try tags.append(allocator, try allocator.dupe(u8, "win_arm64"));
                    },
                    else => {},
                }
            },
            .unknown => {},
        }

        return try tags.toOwnedSlice(allocator);
    }

    /// Get Python tags for this platform
    pub fn getPythonTags(self: Platform, allocator: std.mem.Allocator) ![][]const u8 {
        var tags = std.ArrayList([]const u8){};
        errdefer {
            for (tags.items) |t| allocator.free(t);
            tags.deinit(allocator);
        }

        // CPython specific: cp311
        const cp_tag = try std.fmt.allocPrint(allocator, "cp{d}{d}", .{ self.python_major, self.python_minor });
        try tags.append(allocator, cp_tag);

        // Generic Python: py311
        const py_tag = try std.fmt.allocPrint(allocator, "py{d}{d}", .{ self.python_major, self.python_minor });
        try tags.append(allocator, py_tag);

        // Major version only: py3
        const py_major = try std.fmt.allocPrint(allocator, "py{d}", .{self.python_major});
        try tags.append(allocator, py_major);

        return try tags.toOwnedSlice(allocator);
    }

    /// Get ABI tags for this platform
    pub fn getAbiTags(self: Platform, allocator: std.mem.Allocator) ![][]const u8 {
        var tags = std.ArrayList([]const u8){};
        errdefer {
            for (tags.items) |t| allocator.free(t);
            tags.deinit(allocator);
        }

        // CPython ABI: cp311
        const cp_abi = try std.fmt.allocPrint(allocator, "cp{d}{d}", .{ self.python_major, self.python_minor });
        try tags.append(allocator, cp_abi);

        // ABI3 (stable ABI)
        try tags.append(allocator, try allocator.dupe(u8, "abi3"));

        // None (pure Python)
        try tags.append(allocator, try allocator.dupe(u8, "none"));

        return try tags.toOwnedSlice(allocator);
    }
};

/// Parse wheel filename into components
pub fn parseWheelFilename(allocator: std.mem.Allocator, filename: []const u8, url: []const u8, size: u64, sha256: ?[]const u8) !WheelInfo {
    // Strip .whl extension
    const base = if (std.mem.endsWith(u8, filename, ".whl"))
        filename[0 .. filename.len - 4]
    else
        return error.InvalidWheelFilename;

    // Split by '-'
    var parts = std.mem.splitScalar(u8, base, '-');

    // distribution
    const dist = parts.next() orelse return error.InvalidWheelFilename;
    const distribution = try allocator.dupe(u8, dist);
    errdefer allocator.free(distribution);

    // version
    const ver = parts.next() orelse return error.InvalidWheelFilename;
    const version = try allocator.dupe(u8, ver);
    errdefer allocator.free(version);

    // Remaining parts: [build]-python-abi-platform
    // Build tag is optional (numeric)
    var remaining: [4]?[]const u8 = .{ null, null, null, null };
    var remaining_count: usize = 0;
    while (parts.next()) |part| {
        if (remaining_count < 4) {
            remaining[remaining_count] = part;
            remaining_count += 1;
        }
    }

    // Determine if we have a build tag
    var build: ?[]const u8 = null;
    var python_str: []const u8 = undefined;
    var abi_str: []const u8 = undefined;
    var platform_str: []const u8 = undefined;

    if (remaining_count == 4) {
        // Has build tag
        const build_str = remaining[0] orelse return error.InvalidWheelFilename;
        build = try allocator.dupe(u8, build_str);
        python_str = remaining[1] orelse return error.InvalidWheelFilename;
        abi_str = remaining[2] orelse return error.InvalidWheelFilename;
        platform_str = remaining[3] orelse return error.InvalidWheelFilename;
    } else if (remaining_count == 3) {
        // No build tag
        python_str = remaining[0] orelse return error.InvalidWheelFilename;
        abi_str = remaining[1] orelse return error.InvalidWheelFilename;
        platform_str = remaining[2] orelse return error.InvalidWheelFilename;
    } else {
        return error.InvalidWheelFilename;
    }
    errdefer if (build) |b| allocator.free(b);

    // Parse tags (can be compound with '.')
    const python_tags = try parseTags(allocator, python_str);
    errdefer {
        for (python_tags) |t| allocator.free(t);
        allocator.free(python_tags);
    }

    const abi_tags = try parseTags(allocator, abi_str);
    errdefer {
        for (abi_tags) |t| allocator.free(t);
        allocator.free(abi_tags);
    }

    const platform_tags = try parseTags(allocator, platform_str);
    errdefer {
        for (platform_tags) |t| allocator.free(t);
        allocator.free(platform_tags);
    }

    const filename_copy = try allocator.dupe(u8, filename);
    errdefer allocator.free(filename_copy);

    const url_copy = try allocator.dupe(u8, url);
    errdefer allocator.free(url_copy);

    const sha256_copy = if (sha256) |h| try allocator.dupe(u8, h) else null;

    return .{
        .distribution = distribution,
        .version = version,
        .build = build,
        .python_tags = python_tags,
        .abi_tags = abi_tags,
        .platform_tags = platform_tags,
        .filename = filename_copy,
        .url = url_copy,
        .size = size,
        .sha256 = sha256_copy,
    };
}

/// Parse compound tags (e.g., "cp39.cp310.cp311" -> ["cp39", "cp310", "cp311"])
fn parseTags(allocator: std.mem.Allocator, tag_str: []const u8) ![][]const u8 {
    var tags = std.ArrayList([]const u8){};
    errdefer {
        for (tags.items) |t| allocator.free(t);
        tags.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, tag_str, '.');
    while (iter.next()) |tag| {
        if (tag.len > 0) {
            try tags.append(allocator, try allocator.dupe(u8, tag));
        }
    }

    return try tags.toOwnedSlice(allocator);
}

/// Wheel selector - picks best wheel for platform
pub const WheelSelector = struct {
    allocator: std.mem.Allocator,
    platform: Platform,
    python_tags: [][]const u8,
    abi_tags: [][]const u8,
    platform_tags: [][]const u8,

    pub fn init(allocator: std.mem.Allocator) !WheelSelector {
        const platform = Platform.detect();
        const python_tags = try platform.getPythonTags(allocator);
        errdefer {
            for (python_tags) |t| allocator.free(t);
            allocator.free(python_tags);
        }

        const abi_tags = try platform.getAbiTags(allocator);
        errdefer {
            for (abi_tags) |t| allocator.free(t);
            allocator.free(abi_tags);
        }

        const platform_tags = try platform.getPlatformTags(allocator);

        return .{
            .allocator = allocator,
            .platform = platform,
            .python_tags = python_tags,
            .abi_tags = abi_tags,
            .platform_tags = platform_tags,
        };
    }

    pub fn deinit(self: *WheelSelector) void {
        for (self.python_tags) |t| self.allocator.free(t);
        self.allocator.free(self.python_tags);
        for (self.abi_tags) |t| self.allocator.free(t);
        self.allocator.free(self.abi_tags);
        for (self.platform_tags) |t| self.allocator.free(t);
        self.allocator.free(self.platform_tags);
    }

    /// Select best wheel from a list of files
    pub fn selectBestWheel(self: *WheelSelector, files: []const pypi.FileInfo) ?struct { index: usize, score: i32 } {
        var best_index: ?usize = null;
        var best_score: i32 = -1;

        for (files, 0..) |file, i| {
            if (!file.isWheel()) continue;

            const score = self.scoreWheel(file);
            if (score > best_score) {
                best_score = score;
                best_index = i;
            }
        }

        if (best_index) |idx| {
            return .{ .index = idx, .score = best_score };
        }
        return null;
    }

    /// Score a wheel for compatibility (higher = better)
    fn scoreWheel(self: *WheelSelector, file: pypi.FileInfo) i32 {
        // Parse wheel info from filename
        const info = parseWheelFilename(
            self.allocator,
            file.filename,
            file.url,
            file.size,
            file.sha256,
        ) catch return -1;
        defer @constCast(&info).deinit(self.allocator);

        var score: i32 = 0;

        // Check Python compatibility
        var python_match = false;
        for (info.python_tags) |wheel_tag| {
            for (self.python_tags, 0..) |plat_tag, priority| {
                if (std.mem.eql(u8, wheel_tag, plat_tag)) {
                    python_match = true;
                    // Higher priority tags get higher scores
                    score += @as(i32, @intCast(100 - priority * 10));
                    break;
                }
            }
            if (python_match) break;
        }
        if (!python_match) return -1;

        // Check ABI compatibility
        var abi_match = false;
        for (info.abi_tags) |wheel_tag| {
            for (self.abi_tags, 0..) |plat_tag, priority| {
                if (std.mem.eql(u8, wheel_tag, plat_tag)) {
                    abi_match = true;
                    score += @as(i32, @intCast(50 - priority * 10));
                    break;
                }
            }
            if (abi_match) break;
        }
        if (!abi_match) return -1;

        // Check platform compatibility
        var platform_match = false;
        for (info.platform_tags) |wheel_tag| {
            for (self.platform_tags, 0..) |plat_tag, priority| {
                if (std.mem.eql(u8, wheel_tag, plat_tag)) {
                    platform_match = true;
                    // Platform-specific wheels preferred over 'any'
                    if (std.mem.eql(u8, wheel_tag, "any")) {
                        score += 10;
                    } else {
                        score += @as(i32, @intCast(200 - priority * 5));
                    }
                    break;
                }
            }
            if (platform_match) break;
        }
        if (!platform_match) return -1;

        return score;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "parse wheel filename - simple" {
    const allocator = std.testing.allocator;

    var info = try parseWheelFilename(
        allocator,
        "requests-2.28.0-py3-none-any.whl",
        "https://example.com/requests.whl",
        12345,
        null,
    );
    defer info.deinit(allocator);

    try std.testing.expectEqualStrings("requests", info.distribution);
    try std.testing.expectEqualStrings("2.28.0", info.version);
    try std.testing.expect(info.build == null);
    try std.testing.expectEqual(@as(usize, 1), info.python_tags.len);
    try std.testing.expectEqualStrings("py3", info.python_tags[0]);
    try std.testing.expect(info.isUniversal());
}

test "parse wheel filename - cpython" {
    const allocator = std.testing.allocator;

    var info = try parseWheelFilename(
        allocator,
        "numpy-1.24.0-cp311-cp311-macosx_11_0_arm64.whl",
        "https://example.com/numpy.whl",
        5000000,
        "abc123",
    );
    defer info.deinit(allocator);

    try std.testing.expectEqualStrings("numpy", info.distribution);
    try std.testing.expectEqualStrings("1.24.0", info.version);
    try std.testing.expectEqualStrings("cp311", info.python_tags[0]);
    try std.testing.expectEqualStrings("cp311", info.abi_tags[0]);
    try std.testing.expectEqualStrings("macosx_11_0_arm64", info.platform_tags[0]);
    try std.testing.expect(!info.isUniversal());
}

test "parse wheel filename - with build tag" {
    const allocator = std.testing.allocator;

    var info = try parseWheelFilename(
        allocator,
        "package-1.0.0-123-py3-none-any.whl",
        "https://example.com/pkg.whl",
        1000,
        null,
    );
    defer info.deinit(allocator);

    try std.testing.expectEqualStrings("package", info.distribution);
    try std.testing.expectEqualStrings("1.0.0", info.version);
    try std.testing.expect(info.build != null);
    try std.testing.expectEqualStrings("123", info.build.?);
}

test "Platform detection" {
    const platform = Platform.detect();

    // Just verify it doesn't crash and returns something
    try std.testing.expect(platform.python_major == 3);
    try std.testing.expect(platform.python_minor >= 0);
}

test "WheelSelector creation" {
    const allocator = std.testing.allocator;

    var selector = try WheelSelector.init(allocator);
    defer selector.deinit();

    // Should have at least one tag of each type
    try std.testing.expect(selector.python_tags.len > 0);
    try std.testing.expect(selector.abi_tags.len > 0);
    try std.testing.expect(selector.platform_tags.len > 0);
}

test "WheelInfo Python version matching" {
    const allocator = std.testing.allocator;

    var info = try parseWheelFilename(
        allocator,
        "package-1.0-cp311-none-any.whl",
        "url",
        0,
        null,
    );
    defer info.deinit(allocator);

    try std.testing.expect(info.matchesPythonVersion(3, 11));
    try std.testing.expect(!info.matchesPythonVersion(3, 10));
}

test "WheelInfo universal matching" {
    const allocator = std.testing.allocator;

    var info = try parseWheelFilename(
        allocator,
        "package-1.0-py3-none-any.whl",
        "url",
        0,
        null,
    );
    defer info.deinit(allocator);

    // py3 matches any Python 3.x
    try std.testing.expect(info.matchesPythonVersion(3, 9));
    try std.testing.expect(info.matchesPythonVersion(3, 10));
    try std.testing.expect(info.matchesPythonVersion(3, 11));
    try std.testing.expect(info.matchesPythonVersion(3, 12));
}

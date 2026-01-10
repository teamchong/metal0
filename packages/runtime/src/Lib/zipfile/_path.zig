//! zipfile._path - Path operations for zipfile
//! Reference: cpython/Lib/zipfile/_path.py (internal)
//!
//! Path-like access to zip file contents.

const std = @import("std");

/// Represents a path within a zip file
pub const Path = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: []const u8, // Zip file path
    at: []const u8, // Path within zip

    pub fn init(allocator: std.mem.Allocator, root: []const u8, at: []const u8) Self {
        return .{
            .allocator = allocator,
            .root = root,
            .at = at,
        };
    }

    /// Get the name of this path
    pub fn name(self: *Self) []const u8 {
        return std.fs.path.basename(self.at);
    }

    /// Get the suffix (extension)
    pub fn suffix(self: *Self) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |dot| {
            return n[dot..];
        }
        return "";
    }

    /// Get suffixes (all extensions)
    pub fn suffixes(self: *Self, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var result: std.ArrayList([]const u8) = .{};
        const n = self.name();

        var start: usize = 0;
        for (n, 0..) |c, i| {
            if (c == '.') {
                if (i > start) {
                    start = i;
                }
            }
        }

        if (start > 0) {
            try result.append(allocator, n[start..]);
        }

        return result;
    }

    /// Get the stem (name without extension)
    pub fn stem(self: *Self) []const u8 {
        const n = self.name();
        if (std.mem.lastIndexOf(u8, n, ".")) |dot| {
            if (dot > 0) return n[0..dot];
        }
        return n;
    }

    /// Check if path exists in archive
    pub fn exists(self: *Self) bool {
        _ = self;
        // Would check if path exists in zip
        return false;
    }

    /// Check if path is a directory
    pub fn is_dir(self: *Self) bool {
        return std.mem.endsWith(u8, self.at, "/");
    }

    /// Check if path is a file
    pub fn is_file(self: *Self) bool {
        return !self.is_dir();
    }

    /// Read file contents as text
    pub fn read_text(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }

    /// Read file contents as bytes
    pub fn read_bytes(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }

    /// Open file for reading
    pub fn open(self: *Self) !void {
        _ = self;
        return error.NotImplemented;
    }

    /// Get parent path
    pub fn parent(self: *Self) Self {
        const dir = std.fs.path.dirname(self.at) orelse "";
        return Self.init(self.allocator, self.root, dir);
    }

    /// Join with another path component
    pub fn joinpath(self: *Self, other: []const u8) !Self {
        const joined = try std.fs.path.join(self.allocator, &.{ self.at, other });
        return Self.init(self.allocator, self.root, joined);
    }

    /// Division operator for path joining
    pub fn div(self: *Self, other: []const u8) !Self {
        return self.joinpath(other);
    }

    /// Iterate over directory contents
    pub fn iterdir(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(Self) {
        var result: std.ArrayList(Self) = .{};
        _ = self;
        _ = allocator;
        // Would iterate over zip contents matching this path prefix
        return result;
    }

    /// String representation
    pub fn toString(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.root, self.at });
    }
};

/// Fast lookup for zip file contents
pub const FastLookup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    names: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .names = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.names.deinit();
    }

    pub fn add(self: *Self, name: []const u8) !void {
        try self.names.put(name, {});
    }

    pub fn contains(self: *Self, name: []const u8) bool {
        return self.names.contains(name);
    }
};

/// Compound filter for matching paths
pub const CompoundFilter = struct {
    includes: std.ArrayList([]const u8),
    excludes: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) CompoundFilter {
        return .{
            .includes = std.ArrayList([]const u8).init(allocator),
            .excludes = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CompoundFilter, allocator: std.mem.Allocator) void {
        self.includes.deinit(allocator);
        self.excludes.deinit(allocator);
    }

    pub fn matches(self: *CompoundFilter, path: []const u8) bool {
        // Check excludes first
        for (self.excludes.items) |pattern| {
            if (std.mem.indexOf(u8, path, pattern) != null) {
                return false;
            }
        }

        // Check includes
        if (self.includes.items.len == 0) return true;

        for (self.includes.items) |pattern| {
            if (std.mem.indexOf(u8, path, pattern) != null) {
                return true;
            }
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Path name" {
    const allocator = std.testing.allocator;
    var path = Path.init(allocator, "test.zip", "dir/file.txt");
    try std.testing.expectEqualStrings("file.txt", path.name());
}

test "Path suffix" {
    const allocator = std.testing.allocator;
    var path = Path.init(allocator, "test.zip", "dir/file.txt");
    try std.testing.expectEqualStrings(".txt", path.suffix());
}

test "Path stem" {
    const allocator = std.testing.allocator;
    var path = Path.init(allocator, "test.zip", "dir/file.txt");
    try std.testing.expectEqualStrings("file", path.stem());
}

test "Path is_dir" {
    const allocator = std.testing.allocator;
    var dir = Path.init(allocator, "test.zip", "dir/");
    var file = Path.init(allocator, "test.zip", "dir/file.txt");
    try std.testing.expect(dir.is_dir());
    try std.testing.expect(!file.is_dir());
}

test "FastLookup" {
    const allocator = std.testing.allocator;
    var lookup = FastLookup.init(allocator);
    defer lookup.deinit();

    try lookup.add("file.txt");
    try std.testing.expect(lookup.contains("file.txt"));
    try std.testing.expect(!lookup.contains("other.txt"));
}

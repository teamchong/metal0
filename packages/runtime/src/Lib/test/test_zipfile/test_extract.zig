//! test.test_zipfile.test_extract - ZIP extraction tests
//!
//! Tests for extracting files and directories from ZIP archives including
//! path handling, permissions, and error conditions.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;

// ============================================================================
// Extraction Options
// ============================================================================

pub const ExtractOptions = struct {
    /// Destination directory for extraction
    dest_path: []const u8 = ".",

    /// Overwrite existing files
    overwrite: bool = false,

    /// Preserve timestamps
    preserve_timestamps: bool = true,

    /// Preserve permissions (Unix)
    preserve_permissions: bool = true,

    /// Extract symbolic links
    extract_symlinks: bool = false,

    /// Password for encrypted files
    password: ?[]const u8 = null,

    /// Filter function for selecting files
    filter: ?*const fn ([]const u8) bool = null,

    /// Maximum file size to extract (0 = unlimited)
    max_file_size: u64 = 0,

    /// Follow safe extraction practices
    safe_extract: bool = true,

    pub fn allowExtract(self: ExtractOptions, filename: []const u8, size: u64) bool {
        // Check filter
        if (self.filter) |f| {
            if (!f(filename)) return false;
        }

        // Check size limit
        if (self.max_file_size > 0 and size > self.max_file_size) {
            return false;
        }

        // Safe extraction checks
        if (self.safe_extract) {
            if (!isPathSafe(filename)) return false;
        }

        return true;
    }
};

// ============================================================================
// Path Safety
// ============================================================================

/// Check if extraction path is safe (no directory traversal)
pub fn isPathSafe(path: []const u8) bool {
    // Reject absolute paths
    if (path.len > 0 and (path[0] == '/' or path[0] == '\\')) {
        return false;
    }

    // Check for Windows absolute paths
    if (path.len >= 2 and path[1] == ':') {
        return false;
    }

    // Split and check each component
    var iter = mem.splitSequence(u8, path, "/");
    while (iter.next()) |component| {
        // Check for parent directory references
        if (mem.eql(u8, component, "..")) {
            return false;
        }
        // Check for empty components (double slashes)
        if (component.len == 0) continue;
    }

    // Also check Windows-style separators
    iter = mem.splitSequence(u8, path, "\\");
    while (iter.next()) |component| {
        if (mem.eql(u8, component, "..")) {
            return false;
        }
    }

    return true;
}

/// Normalize path for extraction
pub fn normalizePath(path: []const u8, allocator: mem.Allocator) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var iter = mem.splitAny(u8, path, "/\\");
    var first = true;

    while (iter.next()) |component| {
        if (component.len == 0) continue;
        if (mem.eql(u8, component, ".")) continue;
        if (mem.eql(u8, component, "..")) continue;

        if (!first) {
            try result.append('/');
        }
        try result.appendSlice(component);
        first = false;
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Extractor
// ============================================================================

pub const Extractor = struct {
    const Self = @This();

    allocator: mem.Allocator,
    options: ExtractOptions,
    extracted_files: std.ArrayList(ExtractedFile),
    extracted_dirs: std.ArrayList([]const u8),
    errors: std.ArrayList(ExtractError),

    pub const ExtractedFile = struct {
        source_name: []const u8,
        dest_path: []const u8,
        size: u64,
        is_directory: bool,
    };

    pub const ExtractError = struct {
        filename: []const u8,
        error_type: ErrorType,

        pub const ErrorType = enum {
            path_traversal,
            file_exists,
            permission_denied,
            disk_full,
            encryption_failed,
            corrupted_file,
            unknown,
        };
    };

    pub fn init(allocator: mem.Allocator, options: ExtractOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .extracted_files = std.ArrayList(ExtractedFile).init(allocator),
            .extracted_dirs = std.ArrayList([]const u8).init(allocator),
            .errors = std.ArrayList(ExtractError).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.extracted_files.items) |f| {
            self.allocator.free(f.source_name);
            self.allocator.free(f.dest_path);
        }
        self.extracted_files.deinit();

        for (self.extracted_dirs.items) |d| {
            self.allocator.free(d);
        }
        self.extracted_dirs.deinit();

        for (self.errors.items) |e| {
            self.allocator.free(e.filename);
        }
        self.errors.deinit();
    }

    /// Build full destination path for a file
    pub fn buildDestPath(self: *Self, filename: []const u8) ![]u8 {
        const normalized = try normalizePath(filename, self.allocator);
        defer self.allocator.free(normalized);

        if (self.options.dest_path.len == 0 or mem.eql(u8, self.options.dest_path, ".")) {
            return self.allocator.dupe(u8, normalized);
        }

        // Join paths
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice(self.options.dest_path);
        if (result.items.len > 0 and result.items[result.items.len - 1] != '/') {
            try result.append('/');
        }
        try result.appendSlice(normalized);

        return result.toOwnedSlice();
    }

    /// Create parent directories for a path
    pub fn createParentDirs(self: *Self, path: []const u8) !void {
        const parent = std.fs.path.dirname(path) orelse return;
        if (parent.len == 0) return;

        // Try to create directory
        std.fs.cwd().makePath(parent) catch |err| {
            if (err != error.PathAlreadyExists) {
                try self.errors.append(.{
                    .filename = try self.allocator.dupe(u8, path),
                    .error_type = .permission_denied,
                });
            }
        };
    }

    /// Extract a single file
    pub fn extractFile(self: *Self, name: []const u8, data: []const u8) !void {
        // Safety check
        if (!isPathSafe(name)) {
            try self.errors.append(.{
                .filename = try self.allocator.dupe(u8, name),
                .error_type = .path_traversal,
            });
            return error.PathTraversal;
        }

        // Check options
        if (!self.options.allowExtract(name, data.len)) {
            return error.FilteredOut;
        }

        const dest_path = try self.buildDestPath(name);
        errdefer self.allocator.free(dest_path);

        // Check if it's a directory entry
        if (name.len > 0 and name[name.len - 1] == '/') {
            try self.extractDirectory(name);
            self.allocator.free(dest_path);
            return;
        }

        // Create parent directories
        try self.createParentDirs(dest_path);

        // Check for existing file
        if (!self.options.overwrite) {
            if (fs.cwd().access(dest_path, .{})) |_| {
                try self.errors.append(.{
                    .filename = try self.allocator.dupe(u8, name),
                    .error_type = .file_exists,
                });
                self.allocator.free(dest_path);
                return error.FileExists;
            } else |_| {}
        }

        // Record extraction
        try self.extracted_files.append(.{
            .source_name = try self.allocator.dupe(u8, name),
            .dest_path = dest_path,
            .size = data.len,
            .is_directory = false,
        });
    }

    /// Extract a directory
    pub fn extractDirectory(self: *Self, name: []const u8) !void {
        const dest_path = try self.buildDestPath(name);
        defer self.allocator.free(dest_path);

        fs.cwd().makePath(dest_path) catch |err| {
            if (err != error.PathAlreadyExists) {
                try self.errors.append(.{
                    .filename = try self.allocator.dupe(u8, name),
                    .error_type = .permission_denied,
                });
                return err;
            }
        };

        try self.extracted_dirs.append(try self.allocator.dupe(u8, name));
    }

    /// Get extraction statistics
    pub fn getStats(self: Self) ExtractionStats {
        return .{
            .files_extracted = self.extracted_files.items.len,
            .dirs_created = self.extracted_dirs.items.len,
            .errors = self.errors.items.len,
            .total_bytes = blk: {
                var total: u64 = 0;
                for (self.extracted_files.items) |f| {
                    total += f.size;
                }
                break :blk total;
            },
        };
    }

    /// Check if extraction had errors
    pub fn hasErrors(self: Self) bool {
        return self.errors.items.len > 0;
    }
};

pub const ExtractionStats = struct {
    files_extracted: usize,
    dirs_created: usize,
    errors: usize,
    total_bytes: u64,
};

// ============================================================================
// Member Selection
// ============================================================================

pub const MemberSelector = struct {
    patterns: std.ArrayList([]const u8),
    exclude_patterns: std.ArrayList([]const u8),
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) MemberSelector {
        return .{
            .patterns = std.ArrayList([]const u8).init(allocator),
            .exclude_patterns = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MemberSelector) void {
        self.patterns.deinit();
        self.exclude_patterns.deinit();
    }

    pub fn addPattern(self: *MemberSelector, pattern: []const u8) !void {
        try self.patterns.append(pattern);
    }

    pub fn addExcludePattern(self: *MemberSelector, pattern: []const u8) !void {
        try self.exclude_patterns.append(pattern);
    }

    pub fn matches(self: MemberSelector, filename: []const u8) bool {
        // Check exclude patterns first
        for (self.exclude_patterns.items) |pattern| {
            if (matchGlob(pattern, filename)) return false;
        }

        // If no include patterns, include everything
        if (self.patterns.items.len == 0) return true;

        // Check include patterns
        for (self.patterns.items) |pattern| {
            if (matchGlob(pattern, filename)) return true;
        }

        return false;
    }
};

/// Simple glob matching (supports * and ?)
fn matchGlob(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star_p: ?usize = null;
    var star_t: usize = 0;

    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star_p = p;
            star_t = t;
            p += 1;
        } else if (star_p) |sp| {
            p = sp + 1;
            star_t += 1;
            t = star_t;
        } else {
            return false;
        }
    }

    while (p < pattern.len and pattern[p] == '*') {
        p += 1;
    }

    return p == pattern.len;
}

// ============================================================================
// Tests
// ============================================================================

test "isPathSafe valid paths" {
    try testing.expect(isPathSafe("file.txt"));
    try testing.expect(isPathSafe("dir/file.txt"));
    try testing.expect(isPathSafe("a/b/c/file.txt"));
    try testing.expect(isPathSafe("./file.txt"));
}

test "isPathSafe invalid paths" {
    try testing.expect(!isPathSafe("/etc/passwd"));
    try testing.expect(!isPathSafe("../secret.txt"));
    try testing.expect(!isPathSafe("dir/../../../etc/passwd"));
    try testing.expect(!isPathSafe("C:\\Windows\\System32"));
}

test "normalizePath" {
    const result1 = try normalizePath("a/b/c", testing.allocator);
    defer testing.allocator.free(result1);
    try testing.expectEqualStrings("a/b/c", result1);

    const result2 = try normalizePath("a/../b", testing.allocator);
    defer testing.allocator.free(result2);
    try testing.expectEqualStrings("a/b", result2);

    const result3 = try normalizePath("./a/./b", testing.allocator);
    defer testing.allocator.free(result3);
    try testing.expectEqualStrings("a/b", result3);
}

test "ExtractOptions allowExtract" {
    const opts = ExtractOptions{
        .max_file_size = 1000,
        .safe_extract = true,
    };

    try testing.expect(opts.allowExtract("file.txt", 500));
    try testing.expect(!opts.allowExtract("file.txt", 2000));
    try testing.expect(!opts.allowExtract("../secret.txt", 100));
}

test "Extractor init and deinit" {
    var extractor = Extractor.init(testing.allocator, .{});
    defer extractor.deinit();

    const stats = extractor.getStats();
    try testing.expectEqual(@as(usize, 0), stats.files_extracted);
    try testing.expect(!extractor.hasErrors());
}

test "Extractor buildDestPath" {
    var extractor = Extractor.init(testing.allocator, .{ .dest_path = "/tmp/extract" });
    defer extractor.deinit();

    const path = try extractor.buildDestPath("file.txt");
    defer testing.allocator.free(path);

    try testing.expectEqualStrings("/tmp/extract/file.txt", path);
}

test "Extractor buildDestPath current dir" {
    var extractor = Extractor.init(testing.allocator, .{ .dest_path = "." });
    defer extractor.deinit();

    const path = try extractor.buildDestPath("file.txt");
    defer testing.allocator.free(path);

    try testing.expectEqualStrings("file.txt", path);
}

test "Extractor path traversal error" {
    var extractor = Extractor.init(testing.allocator, .{});
    defer extractor.deinit();

    const result = extractor.extractFile("../secret.txt", "data");
    try testing.expectError(error.PathTraversal, result);
    try testing.expect(extractor.hasErrors());
}

test "MemberSelector init" {
    var selector = MemberSelector.init(testing.allocator);
    defer selector.deinit();

    // Empty selector should match everything
    try testing.expect(selector.matches("anything.txt"));
}

test "MemberSelector with patterns" {
    var selector = MemberSelector.init(testing.allocator);
    defer selector.deinit();

    try selector.addPattern("*.txt");
    try testing.expect(selector.matches("file.txt"));
    try testing.expect(!selector.matches("file.jpg"));
}

test "MemberSelector with exclusions" {
    var selector = MemberSelector.init(testing.allocator);
    defer selector.deinit();

    try selector.addExcludePattern("*.tmp");
    try testing.expect(selector.matches("file.txt"));
    try testing.expect(!selector.matches("file.tmp"));
}

test "matchGlob simple" {
    try testing.expect(matchGlob("*.txt", "file.txt"));
    try testing.expect(!matchGlob("*.txt", "file.jpg"));
    try testing.expect(matchGlob("file?", "file1"));
    try testing.expect(matchGlob("*", "anything"));
}

test "matchGlob complex" {
    try testing.expect(matchGlob("a*b*c", "aXXbYYc"));
    try testing.expect(matchGlob("*.t?t", "file.txt"));
    try testing.expect(!matchGlob("*.t?t", "file.text"));
}

test "ExtractionStats" {
    const stats = ExtractionStats{
        .files_extracted = 10,
        .dirs_created = 3,
        .errors = 1,
        .total_bytes = 12345,
    };

    try testing.expectEqual(@as(usize, 10), stats.files_extracted);
    try testing.expectEqual(@as(u64, 12345), stats.total_bytes);
}

test "ExtractError types" {
    const err = Extractor.ExtractError{
        .filename = "test.txt",
        .error_type = .path_traversal,
    };

    try testing.expectEqual(Extractor.ExtractError.ErrorType.path_traversal, err.error_type);
}

test "ExtractOptions filter" {
    const filter = struct {
        fn f(name: []const u8) bool {
            return mem.endsWith(u8, name, ".txt");
        }
    }.f;

    const opts = ExtractOptions{
        .filter = filter,
    };

    try testing.expect(opts.allowExtract("file.txt", 100));
    try testing.expect(!opts.allowExtract("file.jpg", 100));
}

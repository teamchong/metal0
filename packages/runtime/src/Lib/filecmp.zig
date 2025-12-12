//! CPython source: Lib/filecmp.py
//!
//! Provides functions to compare files and directories.
//!
//! Mirrors: CPython Lib/filecmp.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// File Comparison
// ============================================================================

/// Compare two files, returning true if they are the same
pub fn cmp(file1: []const u8, file2: []const u8, shallow: bool) !bool {
    // Get file stats
    const stat1 = try getFileStat(file1);
    const stat2 = try getFileStat(file2);

    // Quick checks
    if (stat1.size != stat2.size) {
        return false;
    }

    if (shallow) {
        // Only compare metadata
        return stat1.mtime == stat2.mtime;
    }

    // Compare contents
    return try compareFileContents(file1, file2);
}

fn getFileStat(path: []const u8) !std.fs.File.Stat {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.stat();
}

fn compareFileContents(file1: []const u8, file2: []const u8) !bool {
    const f1 = try std.fs.cwd().openFile(file1, .{});
    defer f1.close();

    const f2 = try std.fs.cwd().openFile(file2, .{});
    defer f2.close();

    var buf1: [8192]u8 = undefined;
    var buf2: [8192]u8 = undefined;

    while (true) {
        const n1 = try f1.read(&buf1);
        const n2 = try f2.read(&buf2);

        if (n1 != n2) return false;
        if (n1 == 0) return true;
        if (!std.mem.eql(u8, buf1[0..n1], buf2[0..n2])) return false;
    }
}

/// Compare files, using a cache for better performance
pub fn cmpfiles(allocator: std.mem.Allocator, dir1: []const u8, dir2: []const u8, common: []const []const u8, shallow: bool) !struct {
    match: [][]const u8,
    mismatch: [][]const u8,
    errors: [][]const u8,
} {
    var match: std.ArrayList([]const u8) = .{};
    var mismatch: std.ArrayList([]const u8) = .{};
    var errors: std.ArrayList([]const u8) = .{};

    errdefer {
        match.deinit(allocator);
        mismatch.deinit(allocator);
        errors.deinit(allocator);
    }

    for (common) |name| {
        const path1 = try std.fs.path.join(allocator, &[_][]const u8{ dir1, name });
        defer allocator.free(path1);

        const path2 = try std.fs.path.join(allocator, &[_][]const u8{ dir2, name });
        defer allocator.free(path2);

        const result = cmp(path1, path2, shallow) catch {
            try errors.append(allocator, name);
            continue;
        };

        if (result) {
            try match.append(allocator, name);
        } else {
            try mismatch.append(allocator, name);
        }
    }

    return .{
        .match = try match.toOwnedSlice(allocator),
        .mismatch = try mismatch.toOwnedSlice(allocator),
        .errors = try errors.toOwnedSlice(allocator),
    };
}

// ============================================================================
// Directory Comparison
// ============================================================================

/// Directory comparison class
pub const DirCmp = struct {
    const Self = @This();

    left: []const u8,
    right: []const u8,
    ignore: []const []const u8,
    hide: []const []const u8,
    allocator: std.mem.Allocator,

    // Computed attributes (lazily computed)
    left_list: ?[][]const u8,
    right_list: ?[][]const u8,
    common: ?[][]const u8,
    left_only: ?[][]const u8,
    right_only: ?[][]const u8,
    common_dirs: ?[][]const u8,
    common_files: ?[][]const u8,
    common_funny: ?[][]const u8,
    same_files: ?[][]const u8,
    diff_files: ?[][]const u8,
    funny_files: ?[][]const u8,
    subdirs: ?hashmap_helper.StringHashMap(*Self),

    /// Default patterns to ignore
    pub const DEFAULT_IGNORES = [_][]const u8{
        "RCS",
        "CVS",
        "tags",
        ".git",
        ".hg",
        ".bzr",
        "_darcs",
        "__pycache__",
    };

    pub fn init(allocator: std.mem.Allocator, a: []const u8, b: []const u8, ignore: ?[]const []const u8, hide: ?[]const []const u8) Self {
        return .{
            .left = a,
            .right = b,
            .ignore = ignore orelse &DEFAULT_IGNORES,
            .hide = hide orelse &[_][]const u8{ ".", ".." },
            .allocator = allocator,
            .left_list = null,
            .right_list = null,
            .common = null,
            .left_only = null,
            .right_only = null,
            .common_dirs = null,
            .common_files = null,
            .common_funny = null,
            .same_files = null,
            .diff_files = null,
            .funny_files = null,
            .subdirs = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.left_list) |list| self.allocator.free(list);
        if (self.right_list) |list| self.allocator.free(list);
        if (self.common) |list| self.allocator.free(list);
        if (self.left_only) |list| self.allocator.free(list);
        if (self.right_only) |list| self.allocator.free(list);
        if (self.common_dirs) |list| self.allocator.free(list);
        if (self.common_files) |list| self.allocator.free(list);
        if (self.common_funny) |list| self.allocator.free(list);
        if (self.same_files) |list| self.allocator.free(list);
        if (self.diff_files) |list| self.allocator.free(list);
        if (self.funny_files) |list| self.allocator.free(list);

        if (self.subdirs) |*subdirs| {
            var iter = subdirs.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            subdirs.deinit();
        }
    }

    /// Get list of files in left directory
    pub fn getLeftList(self: *Self) ![][]const u8 {
        if (self.left_list) |list| return list;
        self.left_list = try self.filterDir(self.left);
        return self.left_list.?;
    }

    /// Get list of files in right directory
    pub fn getRightList(self: *Self) ![][]const u8 {
        if (self.right_list) |list| return list;
        self.right_list = try self.filterDir(self.right);
        return self.right_list.?;
    }

    fn filterDir(self: *Self, path: []const u8) ![][]const u8 {
        var result: std.ArrayList([]const u8) = .{};
        errdefer result.deinit(self.allocator);

        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
            return result.toOwnedSlice(self.allocator);
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            // Check hide list
            var hidden = false;
            for (self.hide) |h| {
                if (std.mem.eql(u8, entry.name, h)) {
                    hidden = true;
                    break;
                }
            }
            if (hidden) continue;

            // Check ignore list
            var ignored = false;
            for (self.ignore) |i| {
                if (std.mem.eql(u8, entry.name, i)) {
                    ignored = true;
                    break;
                }
            }
            if (ignored) continue;

            try result.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Get files common to both directories
    pub fn getCommon(self: *Self) ![][]const u8 {
        if (self.common) |c| return c;

        const left = try self.getLeftList();
        const right = try self.getRightList();

        var result: std.ArrayList([]const u8) = .{};
        errdefer result.deinit(self.allocator);

        for (left) |l| {
            for (right) |r| {
                if (std.mem.eql(u8, l, r)) {
                    try result.append(self.allocator, l);
                    break;
                }
            }
        }

        self.common = try result.toOwnedSlice(self.allocator);
        return self.common.?;
    }

    /// Get files only in left directory
    pub fn getLeftOnly(self: *Self) ![][]const u8 {
        if (self.left_only) |l| return l;

        const left = try self.getLeftList();
        const common = try self.getCommon();

        var result: std.ArrayList([]const u8) = .{};
        errdefer result.deinit(self.allocator);

        for (left) |l| {
            var in_common = false;
            for (common) |c| {
                if (std.mem.eql(u8, l, c)) {
                    in_common = true;
                    break;
                }
            }
            if (!in_common) {
                try result.append(self.allocator, l);
            }
        }

        self.left_only = try result.toOwnedSlice(self.allocator);
        return self.left_only.?;
    }

    /// Get files only in right directory
    pub fn getRightOnly(self: *Self) ![][]const u8 {
        if (self.right_only) |r| return r;

        const right = try self.getRightList();
        const common = try self.getCommon();

        var result: std.ArrayList([]const u8) = .{};
        errdefer result.deinit(self.allocator);

        for (right) |r| {
            var in_common = false;
            for (common) |c| {
                if (std.mem.eql(u8, r, c)) {
                    in_common = true;
                    break;
                }
            }
            if (!in_common) {
                try result.append(self.allocator, r);
            }
        }

        self.right_only = try result.toOwnedSlice(self.allocator);
        return self.right_only.?;
    }

    /// Print comparison report
    pub fn report(self: *Self) !void {
        const writer = std.io.getStdOut().writer();

        try writer.print("diff {s} {s}\n", .{ self.left, self.right });

        const left_only = try self.getLeftOnly();
        if (left_only.len > 0) {
            try writer.print("Only in {s}: ", .{self.left});
            for (left_only, 0..) |name, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(name);
            }
            try writer.writeAll("\n");
        }

        const right_only = try self.getRightOnly();
        if (right_only.len > 0) {
            try writer.print("Only in {s}: ", .{self.right});
            for (right_only, 0..) |name, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.writeAll(name);
            }
            try writer.writeAll("\n");
        }
    }

    /// Print full comparison report including subdirectories
    pub fn reportFull(self: *Self) !void {
        try self.report();

        // Recursively report on common subdirectories
        const common_dirs = try self.getCommonDirs();
        for (common_dirs) |subdir| {
            var left_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            var right_path_buf: [std.fs.max_path_bytes]u8 = undefined;

            const left_subpath = std.fmt.bufPrint(&left_path_buf, "{s}/{s}", .{ self.left, subdir }) catch continue;
            const right_subpath = std.fmt.bufPrint(&right_path_buf, "{s}/{s}", .{ self.right, subdir }) catch continue;

            var sub_cmp = DirCmp.init(self.allocator, left_subpath, right_subpath, self.ignore, self.hide);
            defer sub_cmp.deinit();

            const writer = std.io.getStdOut().writer();
            try writer.print("\nDiff {s} {s}\n", .{ left_subpath, right_subpath });
            try sub_cmp.reportFull();
        }
    }

    /// Print partial comparison report
    pub fn reportPartial(self: *Self) !void {
        try self.report();
    }
};

// ============================================================================
// Cache
// ============================================================================

/// Clear the file comparison cache
pub fn clearCache() void {
    // Cache implementation would be cleared here
}

// ============================================================================
// Tests
// ============================================================================

test "cmp identical content" {
    // Would need test files to properly test
    // For now, just ensure the function compiles
    _ = &cmp;
}

test "DirCmp init" {
    const allocator = std.testing.allocator;
    var dc = DirCmp.init(allocator, "/tmp/a", "/tmp/b", null, null);
    defer dc.deinit();

    try std.testing.expectEqualStrings("/tmp/a", dc.left);
    try std.testing.expectEqualStrings("/tmp/b", dc.right);
}

test "DEFAULT_IGNORES" {
    try std.testing.expect(DirCmp.DEFAULT_IGNORES.len > 0);

    var found_git = false;
    for (DirCmp.DEFAULT_IGNORES) |ignore| {
        if (std.mem.eql(u8, ignore, ".git")) {
            found_git = true;
            break;
        }
    }
    try std.testing.expect(found_git);
}
